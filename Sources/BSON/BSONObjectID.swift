import Foundation
import NIO
import NIOConcurrencyHelpers

/// A struct to represent the BSON ObjectID type.
public struct BSONObjectID: Equatable, Hashable, CustomStringConvertible {
    internal static let LENGTH = 12

    /// This `BSONObjectID`'s data represented as a `String`.
    public var hex: String { self.oid.reduce("") { $0 + String(format: "%02x", $1) } }

    public var description: String { self.hex }

    /// ObjectID Bytes
    internal let oid: [UInt8]

    internal static let generator = ObjectIDGenerator()

    /// Initializes a new `BSONObjectID`.
    public init() {
        self.oid = Self.generator.generate()
    }

    /// Initializes a new `BSONObjectID`.
    internal init(_ bytes: [UInt8]) {
        precondition(
            bytes.count == BSONObjectID.LENGTH,
            "BSONObjectIDs must be \(BSONObjectID.LENGTH) bytes long, got \(bytes.count)"
        )
        self.oid = bytes
    }

    /// Initializes an `BSONObjectID` from the provided hex `String`.
    /// - Throws:
    ///   - `BSONError.InvalidArgumentError` if string passed is not a valid BSONObjectID
    /// - SeeAlso: https://github.com/mongodb/specifications/blob/master/source/objectid.rst
    public init(_ hex: String) throws {
        guard hex.utf8.count == (BSONObjectID.LENGTH * 2) else {
            throw BSONError.InvalidArgumentError(
                message: "Cannot create ObjectId from \(hex). Length must be \(BSONObjectID.LENGTH * 2)"
            )
        }
        var data = [UInt8](repeating: 0, count: 12)
        for i in 0..<BSONObjectID.LENGTH {
            let j = hex.index(hex.startIndex, offsetBy: i * 2)
            let k = hex.index(j, offsetBy: 2)
            let bytes = hex[j..<k]
            guard let num = UInt8(bytes, radix: 16) else {
                throw BSONError.InvalidArgumentError(message: "Invalid hexadecimal character \(bytes)")
            }
            data[i] = num
        }
        self = BSONObjectID(data)
    }
}

extension BSONObjectID: BSONValue {
    internal static var bsonType: BSONType { .objectID }

    internal var bson: BSON { .objectID(self) }

    internal static func read(from buffer: inout ByteBuffer) throws -> BSON {
        guard let bytes = buffer.readBytes(length: BSONObjectID.LENGTH) else {
            throw BSONError.InternalError(message: "Cannot read \(BSONObjectID.LENGTH) bytes for BSONObjectID")
        }
        return .objectID(BSONObjectID(bytes))
    }

    internal func write(to buffer: inout ByteBuffer) {
        buffer.writeBytes(self.oid)
    }
}

/// A class responsible for generating ObjectIDs for a given instance of this library
/// An ObjectID consists of a random number for this process, a timestamp, and a counter
internal class ObjectIDGenerator {
    /// Random value is 5 bytes of the ObjectID
    private let randomNumber: [UInt8]

    /// Increment counter is only 3 bytes of the ObjectID
    internal var counter: NIOAtomic<UInt32>

    private static let COUNTER_MAX: UInt32 = 0xFFFFFF
    private static let RANDOM_MAX: UInt64 = 0xFF_FFFF_FFFF

    internal init() {
        // 5 bytes of a random number
        self.randomNumber = [UInt8](withUnsafeBytes(
            of: UInt64.random(in: 0...ObjectIDGenerator.RANDOM_MAX), [UInt8].init
        )[0..<5])
        // 3 byte counter started randomly per process
        self.counter = NIOAtomic<UInt32>.makeAtomic(value: UInt32.random(in: 0...ObjectIDGenerator.COUNTER_MAX))
    }

    internal func generate() -> [UInt8] {
        // roll over counter
        _ = self.counter.compareAndExchange(expected: ObjectIDGenerator.COUNTER_MAX + 1, desired: 0x00)
        // fetch current timestamp
        let timestamp = UInt32(Date().timeIntervalSince1970)
        var buffer = [UInt8]()
        buffer.reserveCapacity(BSONObjectID.LENGTH)
        buffer += withUnsafeBytes(of: timestamp.bigEndian, [UInt8].init)
        buffer += self.randomNumber
        buffer += withUnsafeBytes(of: self.counter.add(1).bigEndian, [UInt8].init)[1..<4] // bottom 3 bytes
        return buffer
    }
}
