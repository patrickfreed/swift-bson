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

    /// A set of all the possible extenededJSON wrapper keys.
    private static var wrapperKeySet: Set<String> = {
        return Set(ExtendedJSONDecoder.wrapperKeyMap.keys)
    }()

    /// A map from extended JSON wrapper keys (e.g. "$numberLong") to the BSON type(s) that they correspond to.
    /// Some types are associated with multiple wrapper keys (e.g. "$code" and "$scope" both map to `BSONCodeWithScope`).
    /// Some wrapper keys are associated with multiple types (e.g. "$code" maps to both `BSONCode` and
    /// `BSONCodeWithScope`).
    /// Try decoding each of the types returned from the map until one works to find the proper decoding.
    private static var wrapperKeyMap: [String: [BSONValue.Type]] = {
        var map: [String: [BSONValue.Type]] = [:]
        for t in BSON.allBSONTypes.values {
            for k in t.extJSONTypeWrapperKeys {
                if var existingList = map[k] {
                    existingList.append(t.self)
                    map[k] = existingList
                } else {
                    map[k] = [t]
                }
            }
        }
        return map
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
        // let bson = try json.toBSON(keyPath: [])
        let bson = try self.decodeBSONFromJSON(json, keyPath: [])
        // let bson = BSON(fromExtJSON: json)

        // The `BSON` is then passed through a `BSONDecoder` where it is outputted as a `T`
        let bsonDecoder = BSONDecoder()
        bsonDecoder.userInfo = self.userInfo
        return try bsonDecoder.decode(T.self, fromBSON: bson)
    }

    /// Decode a `BSON` from the given extended JSON.
    private func decodeBSONFromJSON(_ json: JSONValue, keyPath: [String]) throws -> BSON {
        switch try self.decodeScalar(json, keyPath: keyPath) {
        case let .scalar(s):
            return s
        case let .encodedArray(arr):
            let bsonArr = try arr.enumerated().map { (i, jsonValue) in
                try self.decodeBSONFromJSON(jsonValue, keyPath: keyPath + ["\(i)"])
            }
            return .array(bsonArr)
        case let .encodedObject(obj):
            var storage = BSONDocument.BSONDocumentStorage()
            _ = try appendObject(obj, to: &storage)
            return .document(BSONDocument(fromUnsafeBSON: storage, keys: Set(obj.keys)))
        }
    }

    /// Decode and append the given extended JSON object to the provided BSONDocumentStorage.
    private func appendObject(
        _ object: [String: JSONValue],
        to storage: inout BSONDocument.BSONDocumentStorage
    ) throws -> Int {
        return try storage.buildDocument { storage in
            var bytes = 0
            for (k, v) in object {
                bytes += try self.appendElement(v, to: &storage, forKey: k)
            }
            return bytes
        }
    }

    /// Decode the given extended JSON value to BSON and append it to the provided storage.
    private func appendElement(
        _ value: JSONValue,
        to storage: inout BSONDocument.BSONDocumentStorage,
        forKey key: String
    ) throws -> Int {
        switch try self.decodeScalar(value, keyPath: []) {
        case let .scalar(s):
            return storage.append(key: key, value: s)
        case let .encodedArray(arr):
            var bytes = 0
            bytes += storage.appendElementHeader(key: key, bsonType: .array)
            bytes += try storage.buildDocument { storage in
                var bytes = 0
                for (i, v) in arr.enumerated() {
                    bytes += try self.appendElement(v, to: &storage, forKey: String(i))
                }
                return bytes
            }
            return bytes
        case let .encodedObject(obj):
            var bytes = 0
            bytes += storage.appendElementHeader(key: key, bsonType: .document)
            bytes += try self.appendObject(obj, to: &storage)
            return bytes
        }
    }

    /// Attempt to decode a scalar value from either a JSON scalar or an extended JSON encoded scalar.
    /// If the value is a regular document or an array, simply return it as-is for recursive processing. 
    internal func decodeScalar(_ json: JSONValue, keyPath: [String]) throws -> DecodeScalarResult {
        switch json {
        case let .string(s):
            return .scalar(.string(s))
        case let .bool(b):
            return .scalar(.bool(b))
        case let .number(numString):
            if let int32 = Int32(numString) {
                return .scalar(.int32(int32))
            } else if let int64 = Int64(numString) {
                return .scalar(.int64(int64))
            } else if let double = Double(numString) {
                return .scalar(.double(double))
            } else {
                throw DecodingError._extendedJSONError(
                    keyPath: keyPath,
                    debugDescription: "Could not parse number \"\(numString)\""
                )
            }
        case .null:
            return .scalar(.null)
        case let .object(obj):
            if let (key, _) = obj.first, let bsonTypes = Self.wrapperKeyMap[key] {
                for bsonType in bsonTypes {
                    guard let bsonValue = try bsonType.init(fromExtJSON: JSON(json), keyPath: keyPath + [key]) else {
                        continue
                    }
                    return .scalar(bsonValue.bson)
                }
            }

            /// Ensure extended JSON keys aren't interspersed with normal ones.
            guard Self.wrapperKeySet.isDisjoint(with: obj.keys) else {
                throw DecodingError._extendedJSONError(
                    keyPath: keyPath,
                    debugDescription: "Expected extended JSON wrapper object, but got extra keys: \(obj)"
                )
            }

            return .encodedObject(obj)
        case let .array(arr):
            return .encodedArray(arr)
        }
    }

    /// The possible result of attempting to decode a BSON scalar value from a given extended JSON value.
    /// Non-scalar values are preserved as-is.
    internal enum DecodeScalarResult {
        /// A BSON scalar that was successfully decoded from extended JSON.
        case scalar(BSON)

        /// A non-wrapper object extended JSON object.
        case encodedObject([String: JSONValue])

        /// An array containing extended JSON values.
        case encodedArray([JSONValue])
    }
}
