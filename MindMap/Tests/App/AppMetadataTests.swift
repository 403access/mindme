import XCTest
import Foundation

final class AppMetadataTests: XCTestCase {

    func testTimeWindowLabels() {
        XCTAssertEqual(TimeWindow.all.label, "ALL")
        XCTAssertEqual(TimeWindow.year.label, "1Y")
        XCTAssertEqual(TimeWindow.ninety.label, "90D")
        XCTAssertEqual(TimeWindow.thirty.label, "30D")
        XCTAssertEqual(TimeWindow.allCases.map(\.rawValue), ["all", "year", "ninety", "thirty"])
        XCTAssertNil(TimeWindow.all.since)
    }

    func testTimeWindowCutoffs() throws {
        let now = Date()
        let year = try XCTUnwrap(TimeWindow.year.since)
        XCTAssertLessThan(year, now)
        XCTAssertEqual(now.timeIntervalSince(year), 365 * 86_400, accuracy: 3 * 86_400)

        let ninety = try XCTUnwrap(TimeWindow.ninety.since)
        XCTAssertEqual(now.timeIntervalSince(ninety), 90 * 86_400, accuracy: 86_400)

        let thirty = try XCTUnwrap(TimeWindow.thirty.since)
        XCTAssertEqual(now.timeIntervalSince(thirty), 30 * 86_400, accuracy: 86_400)
    }

    func testVisualizationModes() {
        XCTAssertEqual(VisualizationMode.allCases.map(\.label), ["MAP", "CLOUD", "HYBRID"])
        XCTAssertEqual(VisualizationMode.map.title, "Constellation")
        XCTAssertEqual(VisualizationMode.cloud.title, "Word Cloud")
        XCTAssertEqual(VisualizationMode.hybrid.title, "Hybrid Cloud")
        XCTAssertFalse(VisualizationMode.map.icon.isEmpty)
        XCTAssertFalse(VisualizationMode.map.showsCloudWords)
        XCTAssertTrue(VisualizationMode.cloud.showsCloudWords)
        XCTAssertTrue(VisualizationMode.hybrid.showsCloudWords)
        XCTAssertEqual(VisualizationMode.map.id, "map")
    }

    func testToastMessagesHaveUniqueIDsAndDefaults() {
        let first = ToastMessage(text: "One")
        let second = ToastMessage(text: "One")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.kind, .info)
        XCTAssertNil(first.detail)
        XCTAssertEqual(ToastMessage(text: "Two", detail: "details", kind: .error).kind, .error)
    }
}
