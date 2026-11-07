import Foundation
@testable import HassCore
import Testing

struct JSONValueTests {
    @Test func bridgesJSONSerializationValues() throws {
        let data = Data(#"{"on": true, "level": 3, "name": "x", "ids": ["a"], "none": null}"#.utf8)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let value = object.mapValues { JSONValue(any: $0) }
        #expect(value["on"] == .bool(true))
        #expect(value["level"] == .number(3))
        #expect(value["name"] == .string("x"))
        #expect(value["ids"] == .array([.string("a")]))
        #expect(value["none"] == .null)
    }
}
