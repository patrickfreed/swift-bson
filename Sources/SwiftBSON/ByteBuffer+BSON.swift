import NIO

extension ByteBuffer {
    /// Write null terminated UTF-8 string to ByteBuffer starting at writerIndex
    @discardableResult
    internal mutating func writeCString(_ string: String) -> Int {
        let written = self.writeString(string + "\0")
        return written
    }

    /// Attempts to read null terminated UTF-8 string from ByteBuffer starting at the readerIndex
    internal mutating func readCString() throws -> String {
        var string: [UInt8] = []
        for _ in 0..<Int(BSON_MAX_SIZE) {
            // guard let b = self.readByte() else {
            guard let b = self.readByte() else {
                throw BSONError.InternalError(message: "Failed to read CString, unable to read byte from \(self)")
            }

            guard b != 0 else {
                guard let s = String(bytes: string, encoding: .utf8) else {
                    throw BSONError.InternalError(message: "Unable to decode utf8 string from \(string)")
                }
                return s
            }

            string.append(b)
        }
        throw BSONError.InternalError(message: "Failed to read CString, possibly missing null terminator?")
    }

    /// Attempts to read null terminated UTF-8 string from ByteBuffer starting at the readerIndex
    internal mutating func sliceCString() throws -> ByteBuffer? {
        let length: Int? = self.withUnsafeReadableBytes { body in
            for (i, byte) in body.enumerated() {
                // print("byte=\(byte) ascii=\(String(bytes: [byte], encoding: .ascii) ?? "nil")")
                guard byte != 0 else {
                    return i
                }
            }
            return nil
        }

        guard let length = length else {
            throw BSONError.InternalError(message: "Failed to read CString, unable to read byte from \(self)")
        }

        let out = self.readSlice(length: length)
        self.moveReaderIndex(forwardBy: 1)
        return out
        // return self.viewBytes(at: self.re, length: Int)
        // for i in 0..<Int(BSON_MAX_SIZE) {
        //     // guard let b = self.readInteger(endianness: .little, as: UInt8.self) else {
        //     //     throw BSONError.InternalError(message: "Failed to read CString, unable to read byte from \(self)")
        //     // }

        //     guard let b = self.withUnsafeReadableBytes({ body in 
        //         (1, body.first)
        //     }) else {
        //         throw BSONError.InternalError(message: "Failed to read CString, unable to read byte from \(self)")
        //     }
            

        //     guard b != 0 else {
        //         self.moveReaderIndex(to: start)
        //         defer {
        //             self.moveReaderIndex(forwardBy: i + 1)
        //         }
        //         // print("got null byte returning slice \(start) length \(i)")
        //         return self.viewBytes(at: start, length: i)
        //     }
        // }
        // throw BSONError.InternalError(message: "Failed to read CString, possibly missing null terminator?")
    }

    internal mutating func readByte() -> UInt8? {
        self.readWithUnsafeReadableBytes { body in
            guard let byte = body.first else {
                return (0, nil)
            }
            return (1, byte)
        }
    }
}
