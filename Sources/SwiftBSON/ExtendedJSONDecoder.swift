import ExtrasJSON
import Foundation

/// `ExtendedJSONDecoder` facilitates the decoding of ExtendedJSON into `Decodable` values.
public class ExtendedJSONDecoder {
    internal static var extJSONDateFormatterSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    internal static var extJSONDateFormatterMilliseconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Contextual user-provided information for use during decoding.
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Initialize an `ExtendedJSONDecoder`.
    public init() {}

    /// Decodes an instance of the requested type `T` from the provided extended JSON data.
    /// - SeeAlso: https://docs.mongodb.com/manual/reference/mongodb-extended-json/
    ///
    /// - Parameters:
    ///   - type: Codable type to decode the input into.
    ///   - data: `Data` which represents the JSON that will be decoded.
    /// - Returns: Decoded representation of the JSON input as an instance of `T`.
    /// - Throws: `DecodingError` if the JSON data is corrupt or if any value throws an error during decoding.
    public func decode<T: Decodable>(_: T.Type, from data: Data) throws -> T {
        // Data --> JSONValue --> BSON --> T
        // Takes in JSON as `Data` encoded with `.utf8` and runs it through a `JSONDecoder` to get an
        // instance of the `JSON` enum.

        let json = try JSONParser().parse(bytes: data)

        // Then a `BSON` enum instance is created via the `JSON`.
        let bson = try BSON(fromExtJSON: JSON(json), keyPath: [])

        // The `BSON` is then passed through a `BSONDecoder` where it is outputted as a `T`
        let bsonDecoder = BSONDecoder()
        bsonDecoder.userInfo = self.userInfo
        return try bsonDecoder.decode(T.self, fromBSON: bson)
    }
}
