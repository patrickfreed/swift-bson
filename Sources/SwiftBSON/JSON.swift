import Foundation
import ExtrasJSON

public typealias JSON = JSONValue

extension JSON: ExpressibleByFloatLiteral {
    internal init(floatLiteral value: Double) {
        self = .number(value)

extension JSON: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(String(value))
    }
}

extension JSON: ExpressibleByIntegerLiteral {
    internal init(integerLiteral value: Int) {
        // The number `JSON` type is a Double, so we cast any integers to doubles.
        self = .number(String(value))
    }
}

extension JSON: ExpressibleByStringLiteral {
    internal init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSON: ExpressibleByBooleanLiteral {
    internal init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSON: ExpressibleByArrayLiteral {
    internal init(arrayLiteral elements: JSON...) {
        self = .array(elements)
    }
}

extension JSON: ExpressibleByDictionaryLiteral {
    internal init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object([String: JSON](uniqueKeysWithValues: elements))
    }
}

/// Value Getters
extension JSON {
    /// If this `JSON` is a `.double`, return it as a `Double`. Otherwise, return nil.
    internal var doubleValue: Double? {
        guard case let .number(n) = self else {
            return nil
        }
        return Double(n)
    }

    /// If this `JSON` is a `.string`, return it as a `String`. Otherwise, return nil.
    internal var stringValue: String? {
        guard case let .string(s) = self else {
            return nil
        }
        return s
    }

    /// If this `JSON` is a `.bool`, return it as a `Bool`. Otherwise, return nil.
    internal var boolValue: Bool? {
        guard case let .bool(b) = self else {
            return nil
        }
        return b
    }

    /// If this `JSON` is a `.array`, return it as a `[JSON]`. Otherwise, return nil.
    internal var arrayValue: [JSON]? {
        guard case let .array(a) = self else {
            return nil
        }
        return a
    }

    /// If this `JSON` is a `.object`, return it as a `[String: JSON]`. Otherwise, return nil.
    internal var objectValue: [String: JSON]? {
        guard case let .object(o) = self else {
            return nil
        }
        return o
    }
}

/// Helpers
extension JSON {
    /// Helper function used in `BSONValue` initializers that take in extended JSON.
    /// If the current JSON is an object with only the specified key, return its value.
    ///
    /// - Parameters:
    ///   - key: a String representing the one key that the initializer is looking for
    ///   - `keyPath`: an array of `String`s containing the enclosing JSON keys of the current json being passed in.
    ///                This is used for error messages.
    /// - Returns:
    ///    - a JSON which is the value at the given `key` in `self`
    ///    - or `nil` if `self` is not an `object` or does not contain the given `key`
    ///
    /// - Throws: `DecodingError` if `self` has too many keys
    internal func unwrapObject(withKey key: String, keyPath: [String]) throws -> JSON? {
        guard case let .object(obj) = self else {
            return nil
        }
        guard let value = obj[key] else {
            return nil
        }
        guard obj.count == 1 else {
            throw DecodingError._extendedJSONError(
                keyPath: keyPath,
                debugDescription: "Expected only \"\(key)\", found too many keys: \(obj.keys)"
            )
        }
        return value
    }

    /// Helper function used in `BSONValue` initializers that take in extended JSON.
    /// If the current JSON is an object with only the 2 specified keys, return their values.
    ///
    /// - Parameters:
    ///   - key1: a String representing the first key that the initializer is looking for
    ///   - key2: a String representing the second key that the initializer is looking for
    ///   - `keyPath`: an array of `String`s containing the enclosing JSON keys of the current json being passed in.
    ///                This is used for error messages.
    /// - Returns:
    ///    - a tuple containing:
    ///        - a JSON which is the value at the given `key1` in `self`
    ///        - a JSON which is the value at the given `key2` in `self`
    ///    - or `nil` if `self` is not an `object` or does not contain the given keys
    ///
    /// - Throws: `DecodingError` if `self` has too many keys
    internal func unwrapObject(withKeys key1: String, _ key2: String, keyPath: [String]) throws -> (JSON, JSON)? {
        guard case let .object(obj) = self else {
            return nil
        }
        guard
            let value1 = obj[key1],
            let value2 = obj[key2]
        else {
            return nil
        }
        guard obj.count == 2 else {
            throw DecodingError._extendedJSONError(
                keyPath: keyPath,
                debugDescription: "Expected only \"\(key1)\" and \"\(key2)\" found keys: \(obj.keys)"
            )
        }
        return (value1, value2)
    }
}

// extension JSON: Equatable {}
