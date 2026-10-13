// Incremental Server-Sent Events parser: feed lines, get frames. Pure and tested.
import Foundation

nonisolated struct SSEFrame: Equatable, Sendable {
    var event: String = "message"
    var id: String?
    var data: String = ""
}

nonisolated struct SSEParser: Sendable {
    private var event: String?
    private var id: String?
    private var data: [String] = []
    private var sawField = false

    /// Feeds one line (without its newline). Returns a frame when a blank line closes one.
    mutating func feed(line: String) -> SSEFrame? {
        if line.isEmpty {
            defer { event = nil; id = nil; data = []; sawField = false }
            guard sawField else { return nil }
            return SSEFrame(event: event ?? "message", id: id, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil } // comment / heartbeat
        let (field, value) = split(line)
        switch field {
        case "event": event = value
        case "id": id = value
        case "data": data.append(value)
        default: return nil // retry and unknown fields are ignored
        }
        sawField = true
        return nil
    }

    private func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        return (String(line[..<colon]), value)
    }
}
