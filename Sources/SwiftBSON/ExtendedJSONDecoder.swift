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

    private static var wrapperKeys: Set<String> = {
        return Set(BSON.allBSONTypes.values.map { $0.extJSONTypeWrapperKey })
    }()

    private static var wrapperKeyMap: [String: BSONValue.Type] = {
        var map: [String: BSONValue.Type] = [:]
        for t in BSON.allBSONTypes.values {
            map[t.extJSONTypeWrapperKey] = t.self
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

    // func append1(to doc: inout BSONDocument.BSONDocumentStorage, scalar: DecodeScalarResult) throws -> Int // {
    //     switch scalar {
    //     case let .scalar(s):
    //         try s.bsonValue.write(to: &doc.buffer)
    //     case let .encodedArray(l):
    //         fatalError("todo")
    //     case let .encodedObject(obj):
    //         // try doc.buildSubdocument {
    //             for (subk, v) in obj {
    //                 let scalar = try self.decodeScalar(v, keyPath: [subk])
    //                 try self.append1(
    //                     to: &doc,
    //                     scalar: scalar,
    //                     forKey: subk
    //                 )
    //             }
    //         // }
    //     }
    //     return 1
    // }

    // func append(to doc: inout BSONDocument, scalar: DecodeScalarResult, forKey k: String) throws {
    //     try doc.appendF(forKey: k) { buffer in
    //         switch scalar {
    //         case let .scalar(s):
    //             return try buffer.append(key: k, value: s)
    //         case let .encodedArray(l):
    //             fatalError("todo")
    //         case let .encodedObject(obj):
    //             try buffer.buildSubdocument {
    //                 // for (subk, v) in obj {
    //                 //     let scalar = try self.decodeScalar(v, keyPath: [subk])
    //                 //     try self.append(
    //                 //         to: &doc,
    //                 //         scalar: scalar,
    //                 //         forKey: subk
    //                 //     )
    //                 // }
    //                 return 1
    //             }
    //         }
    //         return 1
    //     }
    // }

    private func decodeBSONFromJSON(_ json: JSONValue, keyPath: [String]) throws -> BSON {
        switch try self.decodeScalar(json, keyPath: keyPath) {
        case let .scalar(s):
            return s
        case let .encodedArray(arr):
            fatalError("todo arrays")
        case let .encodedObject(obj):
            func appendObject(_ object: [String: JSONValue], to storage: inout BSONDocument.BSONDocumentStorage) throws -> Int {
                return try storage.buildDocument { storage in
                    var bytes = 0
                    for (k, v) in obj {
                        bytes += try appendElement(v, to: &storage, forKey: k)
                    }
                    return bytes
                }
            }

            func appendElement(_ value: JSONValue, to storage: inout BSONDocument.BSONDocumentStorage, forKey key: String) throws -> Int {
                switch try self.decodeScalar(value, keyPath: []) {
                case let .scalar(s):
                    return storage.append(key: key, value: s)
                case let .encodedArray(l):
                    fatalError("todo")
                case let .encodedObject(obj):
                    var bytes = 0
                    bytes += storage.appendElementHeader(key: key, bsonType: .document)
                    bytes += try appendObject(obj, to: &storage)
                    return bytes
                }
            }

            var storage = BSONDocument.BSONDocumentStorage()
            try appendObject(obj, to: &storage)
            return .document(try BSONDocument(storage: storage))
        }
    }

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
            if obj.count == 1, let (key, _) = obj.first {
                if let t = Self.wrapperKeyMap[key] {
                    return .scalar(try t.init(fromExtJSON: JSON(.object(obj)), keyPath: [])!.bson)
                }
            } else if obj.count == 2 {
                switch obj.first!.key {
                case BSONCode.extJSONTypeWrapperKey, "$scope":
                    return .scalar(try BSONCodeWithScope(fromExtJSON: JSON(json), keyPath: keyPath)!.bson)
                default:
                    break
                }
            }
            guard Self.wrapperKeys.isDisjoint(with: obj.keys) else {
                throw BSONError.InternalError(message: "todo")
            }

            // return .encodedObject(obj)

            var doc = BSONDocument()
            for (k, v) in obj {
                doc[k] = try self.decodeScalar(v, keyPath: []).bson
            }
            return .scalar(.document(doc))
        case let .array(arr):
            return .encodedArray(arr)
        }
    }

    internal enum DecodeScalarResult {
        case scalar(BSON)
        case encodedObject([String: JSONValue])
        case encodedArray([JSONValue])

        var bson: BSON {
            guard case let .scalar(b) = self else {
                fatalError("woo")
            }
            return b
        }
    }
}

extension JSONValue {
    internal enum DecodeScalarResult {
        case scalar(BSON)
        case encodedObject([String: JSONValue])
        case encodedArray([JSONValue])
    }

    fileprivate func toBSON(keyPath: [String]) throws -> BSON {
        switch try self.decodeScalar(keyPath: keyPath) {
        case let .scalar(s):
            return s
        case let .encodedArray(arr):
            fatalError("todo arrays")
        case let .encodedObject(obj):
            var doc = BSONDocument()
            for (k, v) in doc {
                
            }
            return .document(try BSONDocument(fromJSONObj: obj, keyPath: keyPath))
        }
    }

    private static var wrapperKeys: Set<String> = {
        return Set(BSON.allBSONTypes.values.map { $0.extJSONTypeWrapperKey })
    }()

    internal func decodeScalar(keyPath: [String]) throws -> DecodeScalarResult {
        switch self {
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
            if obj.count == 1 {
                switch obj.first! {
                case let (BSONRegularExpression.extJSONTypeWrapperKey, .string(s)):
                    return .scalar(.int32(Int32(s)!))
                case let (BSONObjectID.extJSONTypeWrapperKey, .string(s)):
                    return .scalar(.objectID(try BSONObjectID(s)))
                case let (BSONBinary.extJSONTypeWrapperKey, .string(s)):
                    return .scalar(.int64(Int64(s)!))
                case let (BSONBinary.extJSONTypeWrapperKey, .string(s)):
                    return .scalar(.int64(Int64(s)!))
                case let (BSONCode.extJSONTypeWrapperKey, .string(s)):
                    return .scalar(.int64(Int64(s)!))
                case let (BSONUndefined.extJSONTypeWrapperKey, .string(s)):
                    return .scalar(.int64(Int64(s)!))
                case let (Int32.extJSONTypeWrapperKey, .string(s)):
                    return .scalar(.int32(Int32(s)!))
                case let (Int64.extJSONTypeWrapperKey, .string(s)):
                    return .scalar(.int64(Int64(s)!))
                case let (Double.extJSONTypeWrapperKey, .string(s)):
                    return .scalar(.double(Double(s)!))
                default:
                    return .encodedObject(obj)
                }
            } else if obj.count == 2 {
                switch obj.first!.key {
                case BSONCode.extJSONTypeWrapperKey, "$scope":
                    return .scalar(try BSONCodeWithScope(fromExtJSON: JSON(self), keyPath: keyPath)!.bson)
                default:
                    return .encodedObject(obj)
                }
            } else {
                guard Self.wrapperKeys.isDisjoint(with: obj.keys) else {
                    throw BSONError.InternalError(message: "todo")
                }
            }
            // for (bsonType, bsonValueType) in BSON.allBSONTypes {
            //     guard bsonType != .document && bsonType != .array else {
            //         continue
            //     }
            //     // guard obj.keys.contains(bsonValueType.extJSONTypeWrapperKey) else {
            //     // guard obj[bsonValueType.extJSONTypeWrapperKey] != nil else {
            //     //     continue
            //     // }
            //     guard let value = try bsonValueType.init(fromExtJSON: JSON(.object(obj)), keyPath: keyPath) else {
            //         // throw BSONError.InternalError(message: "failed to decode \(bsonValueType.self) from \(obj)") 
            //         // fatalError("woo")
            //         continue
            //     }
            //     return .scalar(value.bson)
            // }
            return .encodedObject(obj)
        case let .array(arr):
            return .encodedArray(arr)
        }
    }
}
