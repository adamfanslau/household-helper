// One SSE connection per selected household. Reconnects with backoff and a fresh token;
// `ready` triggers a refetch, `change` frames are applied by the stores. Disconnected after
// 3 s surfaces as the "Reconnecting…" pill.
import Foundation
import Observation
import OSLog

@Observable
final class EventsClient {
    enum State: Equatable { case idle, connecting, connected, disconnected }

    private(set) var state: State = .idle
    private(set) var disconnectedSince: Date?
    var onReady: (@MainActor () async -> Void)?
    var onChange: (@MainActor (ChangeEvent) -> Void)?

    private let base: URL
    private let token: ApiClient.TokenProvider
    private var task: Task<Void, Never>?
    private(set) var householdID: String?

    init(base: URL = Env.apiBaseURL, token: @escaping ApiClient.TokenProvider) {
        self.base = base
        self.token = token
    }

    var showsReconnecting: Bool {
        guard state != .connected, let since = disconnectedSince else { return false }
        return Date().timeIntervalSince(since) > 3
    }

    func connect(householdID: String) {
        if self.householdID == householdID, task != nil { return }
        disconnect()
        self.householdID = householdID
        disconnectedSince = Date()
        Log.api.info("events connect \(householdID, privacy: .public)")
        task = Task { [weak self] in await self?.run(householdID: householdID) }
    }

    func disconnect() {
        task?.cancel()
        task = nil
        householdID = nil
        state = .idle
        disconnectedSince = nil
    }

    private func run(householdID: String) async {
        var backoff: Double = 1
        var forceToken = false
        while !Task.isCancelled {
            state = .connecting
            Log.api.debug("events run: requesting token")
            do {
                let tok = try await token(forceToken)
                Log.api.debug("events run: opening stream")
                forceToken = false
                var req = URLRequest(url: base.appending(path: "v1/households/\(householdID)/events"))
                req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 90 // the server pings every 25 s
                let (bytes, response) = try await URLSession.shared.bytes(for: req)
                guard let http = response as? HTTPURLResponse else { throw ApiError.transport("no response") }
                Log.api.debug("events run: status \(http.statusCode)")
                if http.statusCode == 401 { forceToken = true; throw ApiError.unauthenticated }
                guard http.statusCode == 200 else { throw ApiError.http(status: http.statusCode, code: "events", message: "stream refused") }
                var parser = SSEParser()
                var buffer: [UInt8] = []
                var frames: [SSEFrame] = []
                // Manual line splitting: AsyncLineSequence waits for more input than one
                // small SSE frame provides, so `ready` would never be seen.
                for try await byte in bytes {
                    if Task.isCancelled { return }
                    if byte != UInt8(ascii: "\n") {
                        if byte != UInt8(ascii: "\r") { buffer.append(byte) }
                        continue
                    }
                    let line = String(decoding: buffer, as: UTF8.self)
                    buffer.removeAll(keepingCapacity: true)
                    guard let frame = parser.feed(line: line) else { continue }
                    frames.append(frame)
                    Log.api.debug("events frame \(frame.event, privacy: .public)")
                    switch frame.event {
                    case "ready":
                        state = .connected
                        disconnectedSince = nil
                        backoff = 1
                        Log.api.info("events ready")
                        await onReady?()
                    case "change":
                        if let data = frame.data.data(using: .utf8), let ev = try? JSON.decode(ChangeEvent.self, from: data) {
                            onChange?(ev)
                        } else {
                            Log.api.error("events: undecodable change frame")
                        }
                    default:
                        break
                    }
                }
                Log.api.info("events stream ended")
            } catch {
                if Task.isCancelled { return }
                Log.api.error("events: \(error.localizedDescription, privacy: .public)")
            }
            state = .disconnected
            if disconnectedSince == nil { disconnectedSince = Date() }
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 30)
        }
    }
}
