import XCTest
import Foundation

final class FormatTests: XCTestCase {

    func testCount() {
        XCTAssertEqual(Format.count(1, "THREAD", "THREADS"), "1 THREAD")
        XCTAssertEqual(Format.count(0, "THREAD", "THREADS"), "0 THREADS")
        XCTAssertEqual(Format.count(2, "FILE", "FILES"), "2 FILES")
    }

    func testCompactCount() {
        XCTAssertEqual(Format.compactCount(999), "999")
        XCTAssertEqual(Format.compactCount(1_000), "1.0k")
        XCTAssertEqual(Format.compactCount(1_500), "1.5k")
        XCTAssertEqual(Format.compactCount(1_500_000), "1.5M")
        XCTAssertEqual(Format.compactCount(2_000_000_000), "2.0B")
    }

    func testCost() {
        XCTAssertEqual(Format.cost(0), "$0.00")
        XCTAssertEqual(Format.cost(-3), "$0.00")
        XCTAssertEqual(Format.cost(0.0005), "<$0.001")
        XCTAssertEqual(Format.cost(0.01), "$0.010")
        XCTAssertEqual(Format.cost(0.1), "$0.10")
        XCTAssertEqual(Format.cost(1.234), "$1.23")
        XCTAssertEqual(Format.cost(1_500), "$1.5k")
        XCTAssertEqual(Format.cost(2_000_000), "$2.0M")
    }

    func testRelativeTime() {
        let now = Date()
        XCTAssertEqual(Format.relative(now.addingTimeInterval(5)), "just now")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-120)), "2m ago")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-2 * 3_600)), "2h ago")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-3 * 86_400)), "3d ago")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-60 * 86_400)), "2mo ago")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-400 * 86_400)), "1y ago")
    }

    func testDayRange() {
        XCTAssertEqual(Format.dayRange(nil), "—")

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let sameDay = start.addingTimeInterval(3_600)
        XCTAssertEqual(
            Format.dayRange(start...sameDay),
            Format.shortDate.string(from: start)
        )

        let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let range = start...nextDay
        XCTAssertEqual(
            Format.dayRange(range),
            "\(Format.shortDate.string(from: start)) → \(Format.shortDate.string(from: nextDay))"
        )
    }
}
