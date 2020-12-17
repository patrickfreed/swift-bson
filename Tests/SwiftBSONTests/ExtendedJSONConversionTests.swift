import Foundation
import Nimble
import NIO
@testable import SwiftBSON
import XCTest

extension CodingUserInfoKey {
    static let barInfo = CodingUserInfoKey(rawValue: "bar")!
}

open class ExtendedJSONConversionTestCase: BSONTestCase {
    func testExtendedJSONDecoderAndEncoder() throws {
        // Setup
        struct Test: Codable, Equatable {
            let x: Bool
            let y: Int32
            let z: BSONRegularExpression
        }

        let regexStr = "{\"$regularExpression\":{\"pattern\":\"p\",\"options\":\"i\"}}"
        let canonicalExtJSON = "{\"x\":true,\"y\":{\"$numberInt\":\"5\"},\"z\":\(regexStr)}"
        let data = canonicalExtJSON.data(using: .utf8)!
        let regexObj = BSONRegularExpression(pattern: "p", options: "i")
        let test = Test(x: true, y: 5, z: regexObj)

        // Test canonical encoder
        let encoder = ExtendedJSONEncoder()
        encoder.mode = .canonical
        let encoded: Data = try encoder.encode(test)
        expect(encoded).to(cleanEqual(canonicalExtJSON))

        // Test relaxed encoder
        encoder.mode = .relaxed
        let relaxedEncoded: Data = try encoder.encode(test)
        let relaxedExtJSON = "{\"x\":true,\"y\":5,\"z\":\(regexStr)}"
        expect(relaxedEncoded).to(cleanEqual(relaxedExtJSON))

        // Test decoder
        let decoder = ExtendedJSONDecoder()
        let decoded = try decoder.decode(Test.self, from: data)
        expect(decoded).to(equal(test))
    }

    func testExtendedJSONDecodingWithUserInfo() throws {
        struct Foo: Decodable, Equatable {
            let val: BSON
            let bar: Bar

            init(from decoder: Decoder) throws {
                guard let info = decoder.userInfo[.barInfo] as? BSON else {
                    throw TestError(message: "userInfo not present")
                }
                self.val = info

                // test userinfo is propogated to sub containers
                let container = try decoder.singleValueContainer()
                self.bar = try container.decode(Bar.self)
            }
        }

        struct Bar: Decodable, Equatable {
            let val: BSON

            init(from decoder: Decoder) throws {
                guard let info = decoder.userInfo[.barInfo] as? BSON else {
                    throw TestError(message: "userInfo not present")
                }
                self.val = info
            }
        }

        let obj = "{}".data(using: .utf8)!
        let decoder = ExtendedJSONDecoder()

        decoder.userInfo[.barInfo] = BSON.bool(true)
        let boolDecoded = try decoder.decode(Foo.self, from: obj)
        expect(boolDecoded.val).to(equal(true))
        expect(boolDecoded.bar.val).to(equal(true))

        decoder.userInfo[.barInfo] = BSON.string("hello world")
        let stringDecoded = try decoder.decode(Foo.self, from: obj)
        expect(stringDecoded.val).to(equal("hello world"))
        expect(stringDecoded.bar.val).to(equal("hello world"))
    }

    func testExtendedJSONEncodingWithUserInfo() throws {
        struct Foo: Codable, Equatable {
            func encode(to encoder: Encoder) throws {
                let barInfo = encoder.userInfo[.barInfo] as? Bool
                var container = encoder.singleValueContainer()
                try container.encode([barInfo])
            }
        }

        let encoder = ExtendedJSONEncoder()

        encoder.userInfo[.barInfo] = true
        let fooBarEncoded = try encoder.encode(Foo())
        expect(String(data: fooBarEncoded, encoding: .utf8)).to(contain("true"))

        encoder.userInfo[.barInfo] = false
        let fooEncoded = try encoder.encode(Foo())
        expect(String(data: fooEncoded, encoding: .utf8)).to(contain("false"))
    }

    func testOutputFormatting() throws {
        let encoder = ExtendedJSONEncoder()
        let input: BSONDocument = ["topLevel": ["hello": "world"]]

        let defaultFormat = String(data: try encoder.encode(input), encoding: .utf8)
        expect(defaultFormat).to(equal("{\"topLevel\":{\"hello\":\"world\"}}"))

        encoder.outputFormatting = [.prettyPrinted]
        let prettyPrint = String(data: try encoder.encode(input), encoding: .utf8)
        let prettyOutput = """
        {
          "topLevel" : {
            "hello" : "world"
          }
        }
        """
        expect(prettyPrint).to(equal(prettyOutput))

        let multiKeyInput: BSONDocument = ["x": 1, "a": 2]

        encoder.outputFormatting = [.sortedKeys]
        let sorted = String(data: try encoder.encode(multiKeyInput), encoding: .utf8)
        expect(sorted).to(equal("{\"a\":2,\"x\":1}"))

        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let both = String(data: try encoder.encode(multiKeyInput), encoding: .utf8)
        let sortedPrettyOutput = """
        {
          \"a\" : 2,
          \"x\" : 1
        }
        """
        expect(both).to(equal(sortedPrettyOutput))
    }

    func testAnyExtJSON() throws {
        // Success cases
        expect(try BSON(fromExtJSON: "hello", keyPath: [])).to(equal(BSON.string("hello")))
        let document = try BSON(fromExtJSON: ["num": ["$numberInt": "5"], "extra": 1], keyPath: [])
        expect(document.documentValue).toNot(beNil())
        expect(document.documentValue!["num"]).to(equal(.int32(5)))
        expect(document.documentValue!["extra"]).to(equal(.int32(1)))
    }

    func testObjectId() throws {
        let oid = "5F07445CFBBBBBBBBBFAAAAA"

        // Success case
        let bson = try BSONObjectID(fromExtJSON: ["$oid": JSON(.string(oid))], keyPath: [])
        expect(bson).to(equal(try BSONObjectID(oid)))
        expect(bson?.toRelaxedExtendedJSON()).to(equal(["$oid": JSON(.string(oid.lowercased()))]))
        expect(bson?.toCanonicalExtendedJSON()).to(equal(["$oid": JSON(.string(oid.lowercased()))]))

        // Nil cases
        expect(try BSONObjectID(fromExtJSON: ["random": "hello"], keyPath: [])).to(beNil())
        expect(try BSONObjectID(fromExtJSON: "hello", keyPath: [])).to(beNil())

        // Error cases
        expect(try BSONObjectID(fromExtJSON: ["$oid": 1], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONObjectID(fromExtJSON: ["$oid": "hello"], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONObjectID(fromExtJSON: ["$oid": JSON(.string(oid)), "extra": "hello"], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testSymbol() throws {
        // Success case
        expect(try BSONSymbol(fromExtJSON: ["$symbol": "hello"], keyPath: [])).to(equal(BSONSymbol("hello")))
        expect(BSONSymbol("hello").toCanonicalExtendedJSON()).to(equal(["$symbol": "hello"]))

        // Nil case
        expect(try BSONSymbol(fromExtJSON: "hello", keyPath: [])).to(beNil())
    }

    func testString() {
        // Success case
        expect(String(fromExtJSON: "hello", keyPath: [])).to(equal("hello"))
        expect("hello".toCanonicalExtendedJSON()).to(equal("hello"))

        // Nil case
        expect(String(fromExtJSON: ["random": "hello"], keyPath: [])).to(beNil())
    }

    func testInt32() throws {
        // Success cases
        let bson = try Int32(fromExtJSON: 5, keyPath: [])
        expect(bson).to(equal(5))
        expect(bson?.toRelaxedExtendedJSON()).to(equal(5))
        expect(bson?.toCanonicalExtendedJSON()).to(equal(["$numberInt": JSON(.string("5"))]))
        expect(try Int32(fromExtJSON: ["$numberInt": "5"], keyPath: [])).to(equal(5))

        // Nil cases
        expect(try Int32(fromExtJSON: JSON(.number(String(Int64(Int32.max) + 1))), keyPath: [])).to(beNil())
        expect(try Int32(fromExtJSON: true, keyPath: [])).to(beNil())
        expect(try Int32(fromExtJSON: ["bad": "5"], keyPath: [])).to(beNil())

        // Error cases
        expect(try Int32(fromExtJSON: ["$numberInt": 5], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try Int32(fromExtJSON: ["$numberInt": "5", "extra": true], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(
            try Int32(fromExtJSON: ["$numberInt": JSON(.string("\(Double(Int32.max) + 1)"))], keyPath: ["key", "path"]))
            .to(throwError(errorType: DecodingError.self))
    }

    func testInt64() throws {
        // Success cases
        let bson = try Int64(fromExtJSON: 5, keyPath: [])
        expect(bson).to(equal(5))
        expect(bson?.toRelaxedExtendedJSON()).to(equal(5))
        expect(bson?.toCanonicalExtendedJSON()).to(equal(["$numberLong": "5"]))
        expect(try Int64(fromExtJSON: ["$numberLong": "5"], keyPath: [])).to(equal(5))

        // Nil cases
        expect(try Int64(fromExtJSON: JSON(.number(String(Double(Int64.max) + 1))), keyPath: [])).to(beNil())
        expect(try Int64(fromExtJSON: true, keyPath: [])).to(beNil())
        expect(try Int64(fromExtJSON: ["bad": "5"], keyPath: [])).to(beNil())

        // Error cases
        expect(try Int64(fromExtJSON: ["$numberLong": 5], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try Int64(fromExtJSON: ["$numberLong": "5", "extra": true], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try Int64(
            fromExtJSON: ["$numberLong": JSON(.string("\(Double(Int64.max) + 1)"))],
            keyPath: ["key", "path"]
        )).to(throwError(errorType: DecodingError.self))
    }

    /// Tests the BSON Double [finite] and Double [non-finite] types.
    func testDouble() throws {
        // Success cases
        expect(try Double(fromExtJSON: 5.5, keyPath: [])).to(equal(5.5))
        expect(try Double(fromExtJSON: ["$numberDouble": "5.5"], keyPath: [])).to(equal(5.5))
        expect(try Double(fromExtJSON: ["$numberDouble": "Infinity"], keyPath: [])).to(equal(Double.infinity))
        expect(try Double(fromExtJSON: ["$numberDouble": "-Infinity"], keyPath: [])).to(equal(-Double.infinity))
        expect(try Double(fromExtJSON: ["$numberDouble": "NaN"], keyPath: [])?.isNaN).to(beTrue())
        expect(Double("NaN")?.toCanonicalExtendedJSON()).to(equal(["$numberDouble": "NaN"]))
        expect(Double(5.5).toCanonicalExtendedJSON()).to(equal(["$numberDouble": "5.5"]))
        expect(Double(5.5).toRelaxedExtendedJSON()).to(equal(5.5))

        // Nil cases
        expect(try Double(fromExtJSON: true, keyPath: [])).to(beNil())
        expect(try Double(fromExtJSON: ["bad": "5.5"], keyPath: [])).to(beNil())

        // Error cases
        expect(try Double(fromExtJSON: ["$numberDouble": 5.5], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try Double(fromExtJSON: ["$numberDouble": "5.5", "extra": true], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try Double(fromExtJSON: ["$numberDouble": true], keyPath: ["key", "path"]))
            .to(throwError(errorType: DecodingError.self))
    }

    func testDecimal128() throws {
        // Success cases
        expect(try BSONDecimal128(fromExtJSON: ["$numberDecimal": "0.020000000000000004"], keyPath: []))
            .to(equal(try BSONDecimal128("0.020000000000000004")))
        expect(try BSONDecimal128("0.020000000000000004").toCanonicalExtendedJSON())
            .to(equal(["$numberDecimal": "0.020000000000000004"]))

        // Nil cases
        expect(try BSONDecimal128(fromExtJSON: true, keyPath: [])).to(beNil())
        expect(try BSONDecimal128(fromExtJSON: ["bad": "5.5"], keyPath: [])).to(beNil())

        // Error cases
        expect(try BSONDecimal128(fromExtJSON: ["$numberDecimal": 0.020000000000000004], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONDecimal128(fromExtJSON: ["$numberDecimal": "5.5", "extra": true], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONDecimal128(fromExtJSON: ["$numberDecimal": true], keyPath: ["key", "path"]))
            .to(throwError(errorType: DecodingError.self))
    }

    func testBinary() throws {
        // Success case
        try expect(try BSONBinary(fromExtJSON: ["$binary": ["base64": "//8=", "subType": "00"]], keyPath: []))
            .to(equal(BSONBinary(base64: "//8=", subtype: .generic)))
        try expect(try BSONBinary(fromExtJSON: ["$binary": ["base64": "//8=", "subType": "81"]], keyPath: []))
            .to(equal(BSONBinary(base64: "//8=", subtype: .userDefined(129))))
        expect(try BSONBinary(base64: "//8=", subtype: .generic).toCanonicalExtendedJSON())
            .to(equal(["$binary": ["base64": "//8=", "subType": "00"]]))

        // Nil cases
        expect(try BSONBinary(fromExtJSON: 5.5, keyPath: [])).to(beNil())
        expect(try BSONBinary(fromExtJSON: ["random": "hello"], keyPath: [])).to(beNil())

        // Error cases
        expect(try BSONBinary(fromExtJSON: ["$binary": "random"], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONBinary(fromExtJSON: ["$binary": ["base64": "bad", "subType": "00"]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONBinary(fromExtJSON: ["$binary": ["base64": "//8=", "subType": "bad"]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONBinary(fromExtJSON: ["$binary": ["random": "1", "and": "2"]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONBinary(fromExtJSON: ["$binary": "1", "extra": "2"], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testCode() throws {
        // Success case
        expect(try BSONCode(fromExtJSON: ["$code": "javascript"], keyPath: []))
            .to(equal(BSONCode(code: "javascript")))

        // Nil cases
        expect(try BSONCode(fromExtJSON: 5.5, keyPath: [])).to(beNil())
        expect(try BSONCode(fromExtJSON: ["random": 5], keyPath: [])).to(beNil())

        // Error cases
        expect(try BSONCode(fromExtJSON: ["$code": 5], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testCodeWScope() throws {
        // Success case
        expect(try BSONCodeWithScope(fromExtJSON: ["$code": "javascript", "$scope": ["doc": "scope"]], keyPath: []))
            .to(equal(BSONCodeWithScope(
                code: "javascript",
                scope: ["doc": "scope"]
            )))

        // Error cases
        expect(try BSONCodeWithScope(fromExtJSON: ["$code": 5, "$scope": ["doc": "scope"]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONCodeWithScope(fromExtJSON: ["$code": "javascript", "$scope": 1], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testDocument() throws {
        // Success case
        expect(try BSONDocument(fromExtJSON: ["key": ["$numberInt": "5"]], keyPath: []))
            .to(equal(["key": .int32(5)]))
        expect(try BSONDocument(fromJSON: "{\"key\": {\"$numberInt\": \"5\"}}".data(using: .utf8)!))
            .to(equal(["key": .int32(5)]))

        let canonicalExtJSON = """
        {
          "key" : {
            "$numberInt" : "5"
          }
        }
        """
        let relaxedExtJSON = """
        {
          "key" : 5
        }
        """
        let canonicalDoc = try BSONDocument(fromJSON: canonicalExtJSON)
        let relaxedDoc = try BSONDocument(fromJSON: relaxedExtJSON)
        expect(canonicalDoc).to(equal(["key": .int32(5)]))
        expect(relaxedDoc).to(equal(["key": .int32(5)]))

        expect(canonicalDoc.toCanonicalExtendedJSONString()).to(equal(canonicalExtJSON))
        expect(canonicalDoc.toExtendedJSONString()).to(equal(relaxedExtJSON))
        // Nil case
        expect(try BSONDocument(fromExtJSON: 1, keyPath: [])).to(beNil())

        // Error case
        expect(try BSONDocument(fromExtJSON: ["foo": ["bar": ["$timestamp": 5]]], keyPath: []))
            .to(throwError { error in
                expect(error).to(matchError(DecodingError.self))
                expect(String(describing: error)).to(contain("foo.bar"))
            })
    }

    func testTimestamp() throws {
        // Success case
        expect(try BSONTimestamp(fromExtJSON: ["$timestamp": ["t": 1, "i": 2]], keyPath: []))
            .to(equal(BSONTimestamp(timestamp: 1, inc: 2)))

        // Nil cases
        expect(try BSONTimestamp(fromExtJSON: 5.5, keyPath: [])).to(beNil())
        expect(try BSONTimestamp(fromExtJSON: ["random": 5], keyPath: [])).to(beNil())

        // Error cases
        expect(try BSONTimestamp(fromExtJSON: ["$timestamp": 5], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONTimestamp(fromExtJSON: ["$timestamp": ["t": 1]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONTimestamp(fromExtJSON: ["$timestamp": ["t": 1, "i": 2, "3": 3]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONTimestamp(fromExtJSON: ["$timestamp": ["t": 1, "i": 2], "extra": "2"], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testRegularExpression() throws {
        // Success case
        expect(try BSONRegularExpression(
            fromExtJSON: ["$regularExpression": ["pattern": "p", "options": "i"]],
            keyPath: []
        )).to(equal(BSONRegularExpression(pattern: "p", options: "i")))
        expect(try BSONRegularExpression(
            fromExtJSON: ["$regularExpression": ["pattern": "p", "options": ""]],
            keyPath: []
        )).to(equal(BSONRegularExpression(pattern: "p", options: "")))
        expect(try BSONRegularExpression(
            fromExtJSON: ["$regularExpression": ["pattern": "p", "options": "xi"]],
            keyPath: []
        )).to(equal(BSONRegularExpression(pattern: "p", options: "ix")))
        expect(try BSONRegularExpression(
            fromExtJSON: ["$regularExpression": ["pattern": "p", "options": "invalid"]],
            keyPath: []
        )).to(equal(BSONRegularExpression(pattern: "p", options: "invalid")))

        // Nil cases
        expect(try BSONRegularExpression(fromExtJSON: 5.5, keyPath: [])).to(beNil())
        expect(try BSONRegularExpression(fromExtJSON: ["random": 5], keyPath: [])).to(beNil())

        // Error cases
        expect(try BSONRegularExpression(fromExtJSON: ["$regularExpression": 5], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONRegularExpression(fromExtJSON: ["$regularExpression": ["pattern": "p"]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONRegularExpression(
            fromExtJSON: ["$regularExpression": ["pattern": "p", "options": "", "extra": "2"]],
            keyPath: []
        )).to(throwError(errorType: DecodingError.self))
        expect(try BSONRegularExpression(
            fromExtJSON: ["$regularExpression": ["pattern": "p", "options": ""], "extra": "2"],
            keyPath: []
        )).to(throwError(errorType: DecodingError.self))
    }

    func testDBPointer() throws {
        let oid: JSON = ["$oid": "5F07445CFBBBBBBBBBFAAAAA"]
        let objectId: BSONObjectID = try BSONObjectID("5F07445CFBBBBBBBBBFAAAAA")

        // Success case
        expect(try BSONDBPointer(fromExtJSON: ["$dbPointer": ["$ref": "namespace", "$id": oid]], keyPath: []))
            .to(equal(BSONDBPointer(ref: "namespace", id: objectId)))

        // Nil cases
        expect(try BSONDBPointer(fromExtJSON: 5.5, keyPath: [])).to(beNil())
        expect(try BSONDBPointer(fromExtJSON: ["random": 5], keyPath: [])).to(beNil())

        // Error cases
        expect(try BSONDBPointer(fromExtJSON: ["$dbPointer": 5], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONDBPointer(fromExtJSON: ["$dbPointer": ["$ref": "namespace"]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONDBPointer(fromExtJSON: ["$dbPointer": ["$ref": "namespace", "$id": 1]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONDBPointer(fromExtJSON: ["$dbPointer": ["$ref": true, "$id": oid]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONDBPointer(fromExtJSON: ["$dbPointer": ["$ref": "namespace", "$id": ["$oid": "x"]]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONDBPointer(fromExtJSON: ["$dbPointer": ["$ref": "namespace", "$id": oid, "3": 3]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONDBPointer(fromExtJSON: ["$dbPointer": ["$ref": "namespace", "$id": oid], "x": "2"], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testDatetime() throws {
        // Canonical Success case
        let date = Date(msSinceEpoch: 500_004)
        expect(try Date(fromExtJSON: ["$date": ["$numberLong": "500004"]], keyPath: []))
            .to(equal(date))
        expect(date.toCanonicalExtendedJSON()).to(equal(["$date": ["$numberLong": "500004"]]))
        // Relaxed Success case
        let date2 = Date(timeIntervalSince1970: 0)
        expect(try Date(fromExtJSON: ["$date": "1970-01-01T00:00:00Z"], keyPath: []))
            .to(equal(date2))
        expect(date2.toRelaxedExtendedJSON()).to(equal(["$date": "1970-01-01T00:00:00Z"]))

        let date3 = Date(msSinceEpoch: 1_356_351_330_501)
        expect(try Date(fromExtJSON: ["$date": "2012-12-24T12:15:30.501Z"], keyPath: []))
            .to(equal(date3))

        expect(try Date(fromExtJSON: ["$date": 42], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testMinKey() throws {
        // Success cases
        expect(try BSONMinKey(fromExtJSON: ["$minKey": 1], keyPath: [])).to(equal(BSONMinKey()))

        // Nil cases
        expect(try BSONMinKey(fromExtJSON: "minKey", keyPath: [])).to(beNil())
        expect(try BSONMinKey(fromExtJSON: ["bad": "5.5"], keyPath: [])).to(beNil())

        // Error cases
        expect(try BSONMinKey(fromExtJSON: ["$minKey": 1, "extra": 1], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONMinKey(fromExtJSON: ["$minKey": "random"], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testMaxKey() throws {
        // Success cases
        expect(try BSONMaxKey(fromExtJSON: ["$maxKey": 1], keyPath: [])).to(equal(BSONMaxKey()))

        // Nil cases
        expect(try BSONMaxKey(fromExtJSON: "maxKey", keyPath: [])).to(beNil())
        expect(try BSONMaxKey(fromExtJSON: ["bad": "5.5"], keyPath: [])).to(beNil())

        // Error cases
        expect(try BSONMaxKey(fromExtJSON: ["$maxKey": 1, "extra": 1], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONMaxKey(fromExtJSON: ["$maxKey": "random"], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testUndefined() throws {
        // Success cases
        expect(try BSONUndefined(fromExtJSON: ["$undefined": true], keyPath: [])).to(equal(BSONUndefined()))

        // Nil cases
        expect(try BSONUndefined(fromExtJSON: "undefined", keyPath: [])).to(beNil())
        expect(try BSONUndefined(fromExtJSON: ["bad": "5.5"], keyPath: [])).to(beNil())

        // Error cases
        expect(try BSONUndefined(fromExtJSON: ["$undefined": true, "extra": 1], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
        expect(try BSONUndefined(fromExtJSON: ["$undefined": 1], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testArray() throws {
        // Success cases
        expect(try Array(fromExtJSON: [1, ["$numberLong": "2"], "3"], keyPath: []))
            .to(equal([BSON.int32(1), BSON.int64(2), BSON.string("3")]))
        expect(try Array(fromExtJSON: [["$numberInt": "1"], ["$numberInt": "2"]], keyPath: []))
            .to(equal([BSON.int32(1), BSON.int32(2)]))
        expect([BSON.int32(1), BSON.int32(2)].toRelaxedExtendedJSON()).to(equal([1, 2]))
        expect([BSON.int32(1), BSON.int32(2)].toCanonicalExtendedJSON())
            .to(equal([["$numberInt": "1"], ["$numberInt": "2"]]))

        // Nil case
        expect(try Array(fromExtJSON: ["doc": "1"], keyPath: [])).to(beNil())

        // Error case
        expect(try Array(fromExtJSON: [["$numberInt": 1]], keyPath: []))
            .to(throwError(errorType: DecodingError.self))
    }

    func testBoolean() {
        // Success cases
        expect(Bool(fromExtJSON: true, keyPath: [])).to(equal(true))

        // Nil cases
        expect(Bool(fromExtJSON: 5.5, keyPath: [])).to(beNil())
        expect(Bool(fromExtJSON: ["bad": "5.5"], keyPath: [])).to(beNil())
    }

    func testNull() {
        // Success cases
        expect(BSONNull(fromExtJSON: JSON(.null), keyPath: [])).to(equal(BSONNull()))

        // Nil cases
        expect(BSONNull(fromExtJSON: 5.5, keyPath: [])).to(beNil())
        expect(BSONNull(fromExtJSON: ["bad": "5.5"], keyPath: [])).to(beNil())
    }
}
