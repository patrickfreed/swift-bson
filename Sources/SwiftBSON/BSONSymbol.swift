import NIO

/// A struct to represent the deprecated Symbol type.
/// Symbols cannot be instantiated, but they can be read from existing documents that contain them.
public struct BSONSymbol: BSONValue, CustomStringConvertible, Equatable, Hashable {
    /*
     * Initializes a `Symbol` from ExtendedJSON.
     *
     * Parameters:
     *   - `json`: a `JSON` representing the canonical or relaxed form of ExtendedJSON for a `Symbol`.
     *   - `keyPath`: an array of `Strings`s containing the enclosing JSON keys of the current json being passed in.
     *              This is used for error messages.
     *
     * Throws:
     *   - `DecodingError` if `json` is a partial match or is malformed.
     *
     * Returns:
     *   - `nil` if the provided value is not an `Symbol`.
     */
    internal init?(fromExtJSON json: JSON, keyPath: [String]) throws {
        guard let value = try json.value.unwrapObject(withKey: "$symbol", keyPath: keyPath) else {
            return nil
        }
        guard let str = value.stringValue else {
            throw DecodingError._extendedJSONError(
                keyPath: keyPath,
                debugDescription:
                "Could not parse `Symbol` from \"\(value)\", input must be a string."
            )
        }
        self = BSONSymbol(str)
    }

    /// Converts this `Symbol` to a corresponding `JSON` in relaxed extendedJSON format.
    internal func toRelaxedExtendedJSON() -> JSON {
        self.toCanonicalExtendedJSON()
    }

    /// Converts this `Symbol` to a corresponding `JSON` in canonical extendedJSON format.
    internal func toCanonicalExtendedJSON() -> JSON {
        ["$symbol": JSON(.string(self.stringValue))]
    }

    internal static var bsonType: BSONType { .symbol }

    internal var bson: BSON { .symbol(self) }

    public var description: String { self.stringValue }

    /// String representation of this `BSONSymbol`.
    public let stringValue: String

    internal init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    internal static func read(from buffer: inout ByteBuffer) throws -> BSON {
        let string = try String.read(from: &buffer)
        guard let stringValue = string.stringValue else {
            throw BSONError.InternalError(message: "Cannot get string value of BSON symbol")
        }
        return .symbol(BSONSymbol(stringValue))
    }

    internal func write(to buffer: inout ByteBuffer) {
        self.stringValue.write(to: &buffer)
    }
}
