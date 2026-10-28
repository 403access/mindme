import XCTest
@testable import MindMapCore

// MARK: - Stable identifiers

final class StableIDTests: XCTestCase {

    func testHashIsDeterministicFNV1a() {
        // FNV-1a 64 of a single "a".
        XCTAssertEqual(StableID.hash("a"), 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(StableID.hash("a"), StableID.hash("a"))
        XCTAssertNotEqual(StableID.hash("a"), StableID.hash("b"))
        XCTAssertEqual(StableID.hash(""), 0xcbf2_9ce4_8422_2325)
    }

    func testHexIsZeroPaddedAndStable() {
        XCTAssertEqual(StableID.hex("a"), "af63dc4c8601ec8c")
        XCTAssertEqual(StableID.hex("a").count, 16)
        XCTAssertEqual(StableID.hex("MINDME"), StableID.hex("MINDME"))
        XCTAssertTrue(StableID.hex("").allSatisfy { $0.isHexDigit })
    }
}

// MARK: - Flexible dates

final class FlexibleDateTests: XCTestCase {

    func testISOParsing() {
        XCTAssertEqual(
            FlexibleDate.parse("2026-01-02T10:00:00Z"),
            Date(timeIntervalSince1970: 1_767_348_000)
        )
        XCTAssertEqual(
            FlexibleDate.parse("2026-01-02T10:00:00.500Z")?.timeIntervalSince1970 ?? 0,
            1_767_348_000.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FlexibleDate.parse("2026-01-02T10:00:00+00:00"),
            Date(timeIntervalSince1970: 1_767_348_000)
        )
    }

    func testPlainFormats() {
        XCTAssertEqual(
            FlexibleDate.parse("2026-01-02 10:00:00"),
            Date(timeIntervalSince1970: 1_767_348_000)
        )
        XCTAssertEqual(
            FlexibleDate.parse("2026-01-02T10:00:00"),
            Date(timeIntervalSince1970: 1_767_348_000)
        )
        XCTAssertEqual(
            FlexibleDate.parse("2026-01-02"),
            Date(timeIntervalSince1970: 1_767_312_000)
        )
        XCTAssertNotNil(FlexibleDate.parse("Jan 2, 2026, 10:00:00 AM"))
    }

    func testTimestampsInSecondsMillisecondsAndNanoseconds() {
        let seconds = Date(timeIntervalSince1970: 1_767_348_000)
        XCTAssertEqual(FlexibleDate.fromTimestamp(1_767_348_000), seconds)
        XCTAssertEqual(FlexibleDate.fromTimestamp(1_767_348_000_000), seconds)
        XCTAssertEqual(FlexibleDate.fromTimestamp(1_767_348_000_000_000_000), seconds)
        XCTAssertEqual(FlexibleDate.parse("1767348000"), seconds)
        XCTAssertEqual(FlexibleDate.parse(1_767_348_000), seconds)
        XCTAssertEqual(FlexibleDate.parse(1_767_348_000_000), seconds)
        XCTAssertEqual(FlexibleDate.parse(NSNumber(value: 1_767_348_000)), seconds)
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(FlexibleDate.parse(nil))
        XCTAssertNil(FlexibleDate.parse(""))
        XCTAssertNil(FlexibleDate.parse("   "))
        XCTAssertNil(FlexibleDate.parse("not a date"))
        XCTAssertNil(FlexibleDate.parse(0))
        XCTAssertNil(FlexibleDate.parse(-10))
        XCTAssertNil(FlexibleDate.parse(Double.nan))
        XCTAssertNil(FlexibleDate.parse(Double.infinity))
        XCTAssertNil(FlexibleDate.parse(["unexpected": true]))
    }

    func testDatePassesThrough() {
        let date = Date(timeIntervalSince1970: 42)
        XCTAssertEqual(FlexibleDate.parse(date), date)
    }
}

// MARK: - Text helpers

final class TextToolsTests: XCTestCase {

    func testCollapsedWhitespace() {
        XCTAssertEqual(TextTools.collapsed("  a \n b\t\tc "), "a b c")
        XCTAssertEqual(TextTools.collapsed("a\r\nb"), "a b")
        XCTAssertEqual(TextTools.collapsed("a\u{00a0}b"), "a b")
        XCTAssertEqual(TextTools.collapsed("   "), "")
    }

    func testCountPluralization() {
        XCTAssertEqual(TextTools.count(1, singular: "THREAD", plural: "THREADS"), "1 THREAD")
        XCTAssertEqual(TextTools.count(0, singular: "THREAD", plural: "THREADS"), "0 THREADS")
        XCTAssertEqual(TextTools.count(2, singular: "FILE", plural: "FILES"), "2 FILES")
    }

    func testTruncation() {
        XCTAssertEqual(TextTools.truncated("hello", limit: 10), "hello")
        XCTAssertEqual(TextTools.truncated("hello world", limit: 5), "hello…")
        XCTAssertEqual(TextTools.truncated("hello world", limit: 6), "hello…", "trailing space is trimmed before the ellipsis")
        XCTAssertEqual(TextTools.truncated("  hello   world  ", limit: 5), "hello…")
        XCTAssertEqual(TextTools.truncated("", limit: 5), "")
    }

    func testSlug() {
        XCTAssertEqual(TextTools.slug("SwiftUI & Canvas Performance!"), "swiftui-canvas-performance")
        XCTAssertEqual(TextTools.slug("A B C D E F G H"), "a-b-c-d-e-f")
        XCTAssertEqual(TextTools.slug("---"), "")
        XCTAssertEqual(TextTools.slug("Café Übung"), "café-übung")
    }

    func testHTMLPlainText() {
        let html = """
        <html><head><style>.x { color: red }</style></head>
        <body><h1>Title</h1><p>Hello <b>world</b> &amp; friends.</p>
        <script>alert('nope')</script><div>Line &mdash; two</div></body></html>
        """
        let text = TextTools.plainText(fromHTML: html)
        XCTAssertFalse(text.contains("<"))
        XCTAssertFalse(text.contains("alert"))
        XCTAssertFalse(text.contains("color: red"))
        XCTAssertTrue(text.contains("Hello"))
        XCTAssertTrue(text.contains("world"))
        XCTAssertTrue(text.contains("& friends."))
        XCTAssertTrue(text.contains("Line — two"))
    }

    func testPlainTextDecodesEntities() {
        let text = TextTools.plainText(fromHTML: "&lt;tag&gt; &quot;quoted&quot; &#39;single&#39; &hellip;")
        XCTAssertEqual(text, "<tag> \"quoted\" 'single' …")
    }
}

// MARK: - JSON helpers

final class JSONHelperTests: XCTestCase {

    func testDictionaryAccessors() {
        let dict: [String: Any] = [
            "string": "value",
            "number": 3,
            "double": 3.5,
            "bool": true,
            "object": ["key": "value"],
            "objects": [["a": 1], ["b": 2]],
            "array": [1, 2]
        ]
        XCTAssertEqual(dict.string("string"), "value")
        XCTAssertEqual(dict.string("number"), "3")
        XCTAssertNil(dict.string("missing"))
        XCTAssertEqual(dict.double("number"), 3)
        XCTAssertEqual(dict.double("double"), 3.5)
        XCTAssertEqual(dict.double("string"), nil)
        XCTAssertEqual(dict.int("double"), 3)
        XCTAssertEqual(dict.bool("bool"), true)
        XCTAssertEqual(dict.object("object")?["key"] as? String, "value")
        XCTAssertEqual(dict.objects("objects")?.count, 2)
        XCTAssertEqual(dict.array("array")?.count, 2)
        XCTAssertNil(dict.object("missing"))
    }

    func testJSONInspectStrings() {
        XCTAssertEqual(JSONInspect.strings(in: "  hello  "), ["hello"])
        XCTAssertEqual(JSONInspect.strings(in: "   "), [])
        XCTAssertEqual(JSONInspect.strings(in: nil), [])
        XCTAssertEqual(JSONInspect.strings(in: ["a", ["b", "c"]]), ["a", "b", "c"])
        XCTAssertEqual(JSONInspect.strings(in: ["text": "t"]), ["t"])
        XCTAssertEqual(JSONInspect.strings(in: ["content": ["x", "y"]]), ["x", "y"])
        XCTAssertEqual(JSONInspect.strings(in: ["value": "v"]), ["v"])
        XCTAssertEqual(JSONInspect.strings(in: ["unrelated": "v"]), [])
    }

    func testConversationArrayResolution() {
        XCTAssertEqual(JSONInspect.conversationArray(from: [["id": 1], ["id": 2]])?.count, 2)
        for key in ["conversations", "threads", "chats", "items", "data"] {
            let value = JSONInspect.conversationArray(from: [key: [["id": 1]]])
            XCTAssertEqual(value?.count, 1, key)
        }
        let keyed = JSONInspect.conversationArray(from: ["a": ["id": 1], "b": ["id": 2]])
        XCTAssertEqual(keyed?.count, 2)
        XCTAssertNil(JSONInspect.conversationArray(from: ["foo": "bar"]))
        XCTAssertNil(JSONInspect.conversationArray(from: "string"))
    }
}

// MARK: - Vectors

final class Vec2Tests: XCTestCase {

    func testGeometry() {
        let vector = Vec2(3, 4)
        XCTAssertEqual(vector.length, 5, accuracy: 0.0001)
        XCTAssertEqual(vector.lengthSquared, 25, accuracy: 0.0001)
        XCTAssertEqual(vector.angle, atan2(4, 3), accuracy: 0.0001)
        XCTAssertEqual(vector.normalized.length, 1, accuracy: 0.0001)
        XCTAssertEqual(Vec2.zero.normalized, .zero)
        XCTAssertEqual(vector.dot(Vec2(1, 0)), 3, accuracy: 0.0001)
        XCTAssertEqual(vector.distance(to: Vec2(0, 0)), 5, accuracy: 0.0001)
        XCTAssertEqual(vector.distanceSquared(to: Vec2(0, 0)), 25, accuracy: 0.0001)
    }

    func testRotationAndOperators() {
        let rotated = Vec2(1, 0).rotated(by: .pi / 2)
        XCTAssertEqual(rotated.x, 0, accuracy: 0.0001)
        XCTAssertEqual(rotated.y, 1, accuracy: 0.0001)

        var vector = Vec2(1, 2)
        vector += Vec2(3, 4)
        XCTAssertEqual(vector, Vec2(4, 6))
        vector -= Vec2(1, 1)
        XCTAssertEqual(vector, Vec2(3, 5))
        XCTAssertEqual(Vec2(1, 2) + Vec2(3, 4), Vec2(4, 6))
        XCTAssertEqual(Vec2(3, 4) - Vec2(1, 1), Vec2(2, 3))
        XCTAssertEqual(Vec2(1, 2) * 2, Vec2(2, 4))
        XCTAssertEqual(2 * Vec2(1, 2), Vec2(2, 4))
        XCTAssertEqual(Vec2(2, 4) / 2, Vec2(1, 2))
    }

    func testClampedLength() {
        XCTAssertEqual(Vec2(3, 4).clampedLength(10), Vec2(3, 4))
        XCTAssertEqual(Vec2(3, 4).clampedLength(5), Vec2(3, 4))
        let clamped = Vec2(3, 4).clampedLength(2.5)
        XCTAssertEqual(clamped.length, 2.5, accuracy: 0.0001)
        XCTAssertEqual(Vec2.zero.clampedLength(1), .zero)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Vec2(1.5, -2.5))
        XCTAssertEqual(try JSONDecoder().decode(Vec2.self, from: data), Vec2(1.5, -2.5))
    }
}

final class Vec3Tests: XCTestCase {

    func testGeometry() {
        let vector = Vec3(1, 2, 2)
        XCTAssertEqual(vector.length, 3, accuracy: 0.0001)
        XCTAssertEqual(vector.lengthSquared, 9, accuracy: 0.0001)
        XCTAssertEqual(vector.normalized.length, 1, accuracy: 0.0001)
        XCTAssertEqual(Vec3.zero.normalized, .zero)
        XCTAssertEqual(vector.dot(Vec3(1, 0, 0)), 1, accuracy: 0.0001)
        XCTAssertEqual(vector.distance(to: .zero), 3, accuracy: 0.0001)
        XCTAssertEqual(vector.distanceSquared(to: .zero), 9, accuracy: 0.0001)
        XCTAssertEqual(vector.vec2, Vec2(1, 2))
    }

    func testCrossProduct() {
        XCTAssertEqual(Vec3(1, 0, 0).cross(Vec3(0, 1, 0)), Vec3(0, 0, 1))
        XCTAssertEqual(Vec3(0, 1, 0).cross(Vec3(1, 0, 0)), Vec3(0, 0, -1))
        XCTAssertEqual(Vec3.up, Vec3(0, 1, 0))
    }

    func testOperatorsAndClamping() {
        var vector = Vec3(1, 2, 3)
        vector += Vec3(1, 1, 1)
        XCTAssertEqual(vector, Vec3(2, 3, 4))
        vector -= Vec3(1, 1, 1)
        XCTAssertEqual(vector, Vec3(1, 2, 3))
        XCTAssertEqual(Vec3(1, 2, 3) + Vec3(4, 5, 6), Vec3(5, 7, 9))
        XCTAssertEqual(Vec3(4, 5, 6) - Vec3(1, 2, 3), Vec3(3, 3, 3))
        XCTAssertEqual(Vec3(1, 2, 3) * 2, Vec3(2, 4, 6))
        XCTAssertEqual(2 * Vec3(1, 2, 3), Vec3(2, 4, 6))
        XCTAssertEqual(Vec3(2, 4, 6) / 2, Vec3(1, 2, 3))
        XCTAssertEqual(Vec3(1, 2, 3).clampedLength(100), Vec3(1, 2, 3))
        XCTAssertEqual(Vec3(1, 0, 0).clampedLength(2).length, 1, accuracy: 0.0001)
        XCTAssertEqual(Vec3.zero.clampedLength(1), .zero)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Vec3(1.5, -2.5, 0.25))
        XCTAssertEqual(try JSONDecoder().decode(Vec3.self, from: data), Vec3(1.5, -2.5, 0.25))
    }
}
