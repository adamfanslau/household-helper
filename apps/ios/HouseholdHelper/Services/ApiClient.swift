// URLSession + Codable client for hh-api. Bearer token from the token provider; on a 401 the
// token is force-refreshed once and the request retried, a second 401 surfaces as
// ApiError.unauthenticated (stores then sign out).
import Foundation

nonisolated final class ApiClient: Sendable {
    typealias TokenProvider = @Sendable (_ forceRefresh: Bool) async throws -> String

    private let base: URL
    private let token: TokenProvider
    private let session: URLSession

    init(base: URL = Env.apiBaseURL, session: URLSession = .shared, token: @escaping TokenProvider) {
        self.base = base
        self.session = session
        self.token = token
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try JSON.decode(T.self, from: try await perform("GET", path, body: nil))
    }

    func post<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        try JSON.decode(T.self, from: try await perform("POST", path, body: try JSON.makeEncoder().encode(body)))
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try JSON.decode(T.self, from: try await perform("POST", path, body: nil))
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        try JSON.decode(T.self, from: try await perform("PATCH", path, body: try JSON.makeEncoder().encode(body)))
    }

    /// 204 routes (push tokens).
    func put<B: Encodable>(_ path: String, _ body: B) async throws {
        _ = try await perform("PUT", path, body: try JSON.makeEncoder().encode(body))
    }

    func delete(_ path: String) async throws {
        _ = try await perform("DELETE", path, body: nil)
    }

    private func perform(_ method: String, _ path: String, body: Data?, retry: Bool = true) async throws -> Data {
        var req = URLRequest(url: base.appending(path: path.hasPrefix("/") ? String(path.dropFirst()) : path))
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(try await token(false))", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ApiError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ApiError.transport("no HTTP response") }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401 where retry:
            _ = try await token(true)
            return try await perform(method, path, body: body, retry: false)
        case 401:
            throw ApiError.unauthenticated
        default:
            if let err = try? JSON.decode(ApiErrorBody.self, from: data) {
                throw ApiError.http(status: http.statusCode, code: err.error.code, message: err.error.message)
            }
            throw ApiError.http(status: http.statusCode, code: "http_\(http.statusCode)", message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
    }
}
