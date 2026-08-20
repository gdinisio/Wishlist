//
//  JSONValue.swift
//  Wishlist
//
//  Product APIs and embedded JSON-LD are loosely typed: a field can be a
//  string, a number, an object or an array of any of those, and the shape
//  changes between retailers. Decoding into rigid structs would mean a single
//  unexpected field breaks the whole lookup, so responses are decoded into this
//  tolerant tree and read defensively.
//

import Foundation

nonisolated enum JSONValue: Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

extension JSONValue: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }
}

nonisolated extension JSONValue {
    static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let dictionary) = self else { return nil }
        guard let value = dictionary[key], value != .null else { return nil }
        return value
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let values) = self, values.indices.contains(index) else { return nil }
        return values[index]
    }

    /// Follows a dotted path, e.g. `json.value(at: "product.buybox.price")`.
    /// Numeric components index into arrays.
    func value(at path: String) -> JSONValue? {
        var current: JSONValue? = self
        for component in path.split(separator: ".") {
            guard let step = current else { return nil }
            if let index = Int(component) {
                current = step[index]
            } else {
                current = step[String(component)]
            }
        }
        return current
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .number(let value):
            return value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value):
            return String(value)
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value.replacingOccurrences(of: ",", with: ""))
        default: return nil
        }
    }

    /// Decimal is used for money, so a numeric value goes through its string
    /// form to avoid binary floating-point drift.
    var decimalValue: Decimal? {
        switch self {
        case .number(let value):
            return Decimal(string: String(value))
        case .string(let value):
            return PriceParser.decimal(fromNumericString: value)
        default:
            return nil
        }
    }

    /// Treats a single value as a one-element array, which is how schema.org
    /// handles "one or many" fields.
    var arrayValue: [JSONValue] {
        switch self {
        case .array(let values): return values
        case .null: return []
        default: return [self]
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let dictionary) = self else { return nil }
        return dictionary
    }

    /// First non-empty string found for any of the given keys.
    func firstString(_ keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue { return value }
        }
        return nil
    }
}
