// Wire models for hh-api (apps/api/API.md). Shapes are pinned by the golden fixtures in
// apps/api/internal/httpapi/testdata/golden, decoded by ModelsDecodingTests. Keep in sync.
import Foundation

/// needed → (tap in the shop) in_basket → (checkout) bought.
nonisolated enum ItemStatus: String, Codable, Sendable {
    case needed, inBasket = "in_basket", bought
}

nonisolated struct Me: Codable, Hashable, Sendable {
    let id: String
    let email: String
    let displayName: String
    let provider: String
    let createdAt: Date
    let lastSeenAt: Date
}

nonisolated struct Household: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    let createdBy: String?
    let createdAt: Date
    var updatedAt: Date
    var role: String?
}

nonisolated struct Invite: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let householdId: String
    let code: String
    let createdBy: String?
    let createdAt: Date
    let expiresAt: Date?
    var revokedAt: Date?
}

nonisolated struct Shop: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let householdId: String
    var name: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var neededCount: Int
}

/// A household's product: last quantity (defaultUnit) and last shop are hints for the next add.
nonisolated struct CatalogItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let householdId: String
    var shopId: String?
    var name: String
    var defaultUnit: String?
    let createdAt: Date
    var updatedAt: Date
}

nonisolated struct ShoppingListItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let householdId: String
    var name: String
    var shopId: String?
    var catalogItemId: String?
    var quantity: String?
    var status: ItemStatus
    let addedBy: String?
    let createdAt: Date
    var updatedAt: Date
    var boughtAt: Date?
}

/// One `event: change` frame of the event stream. `row` stays untyped until the table is known.
nonisolated struct ChangeEvent: Decodable, Sendable {
    let id: String
    let table: String
    let type: String
    let row: JSONValue
    let actor: String
}

nonisolated struct ApiErrorBody: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let code: String
        let message: String
        let fields: [String: String]?
    }
    let error: Detail
}

nonisolated enum ApiError: Error, LocalizedError, Sendable {
    case unauthenticated
    case http(status: Int, code: String, message: String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated: "You are signed out."
        case let .http(_, _, message): message
        case let .transport(message): "Network problem: \(message)"
        case let .decoding(message): "Unexpected response: \(message)"
        }
    }

    var code: String? {
        if case let .http(_, code, _) = self { return code }
        return nil
    }
}

/// Minimal JSON tree, used for SSE rows before they are decoded per table.
nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .object(v): try c.encode(v)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case let .object(o) = self { return o[key] }
        return nil
    }

    var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }
}

nonisolated enum JSON {
    /// RFC 3339 with or without fractional seconds, always UTC on the wire.
    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
            }
            return date
        }
        return d
    }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }
}
