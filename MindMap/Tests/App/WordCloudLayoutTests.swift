import XCTest
import SwiftUI
import MindMapCore

// MARK: - Fixtures

private func tagGraph(includeTags: Bool = true) -> MindMapGraph {
    let start = Date(timeIntervalSince1970: 1_780_000_000)
    let texts = [
        "swift canvas performance",
        "swift canvas rendering",
        "swift rendering pipeline",
        "canvas performance tuning"
    ]
    let threads = texts.enumerated().map { index, text in
        ConversationThread(
            id: "t\(index)",
            provider: index % 2 == 0 ? .chatgpt : .gemini,
            title: "Conversation \(index)",
            createdAt: start,
            updatedAt: start.addingTimeInterval(TimeInterval(index)),
            messages: [ChatMessage(id: "m\(index)", role: .user, text: text)]
        )
    }
    var filters = GraphFilters.default
    filters.includeTags = includeTags
    return GraphBuilder.build(library: ThreadLibrary(threads: threads), filters: filters)
}

private func cloudWord(
    id: String,
    rect: CGRect,
    fontSize: CGFloat = 12
) -> CloudWord {
    CloudWord(
        id: id,
        term: id,
        weight: 1,
        threadCount: 1,
        providers: [.chatgpt],
        fontSize: fontSize,
        rect: rect,
        anchor: CGPoint(x: rect.midX, y: rect.midY),
        color: .red
    )
}

// MARK: - Free word cloud

final class WordCloudLayoutTests: XCTestCase {

    func testEmptyAndTinyCanvasesProduceNoWords() {
        XCTAssertTrue(WordCloudLayout.make(graph: .empty, size: CGSize(width: 900, height: 600)).words.isEmpty)
        XCTAssertTrue(WordCloudLayout.make(graph: tagGraph(), size: CGSize(width: 50, height: 50)).words.isEmpty)
        XCTAssertTrue(WordCloudLayout.make(graph: tagGraph(includeTags: false), size: CGSize(width: 900, height: 600)).words.isEmpty)
    }

    func testWordsFitTheCanvasAndDoNotOverlap() {
        let size = CGSize(width: 900, height: 600)
        let layout = WordCloudLayout.make(graph: tagGraph(), size: size)
        XCTAssertFalse(layout.words.isEmpty)
        XCTAssertLessThanOrEqual(layout.words.count, tagGraph().tagNodes.count)

        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 30, dy: 30)
        for word in layout.words {
            XCTAssertTrue(bounds.contains(word.rect), "\(word.term) escapes the cloud bounds")
            XCTAssertGreaterThan(word.fontSize, 0)
            XCTAssertGreaterThanOrEqual(word.threadCount, 1)
            XCTAssertEqual(word.center.x, word.rect.midX, accuracy: 0.001)
        }
        for i in layout.words.indices {
            for j in layout.words.indices where j > i {
                XCTAssertFalse(
                    layout.words[i].rect.intersects(layout.words[j].rect),
                    "\(layout.words[i].term) overlaps \(layout.words[j].term)"
                )
            }
        }
    }

    func testLargestWordComesFirstAndHitTestingUsesTheTightestRect() throws {
        let layout = WordCloudLayout.make(graph: tagGraph(), size: CGSize(width: 900, height: 600))
        let first = try XCTUnwrap(layout.words.first)
        let last = try XCTUnwrap(layout.words.last)
        XCTAssertGreaterThanOrEqual(first.fontSize, last.fontSize)
        XCTAssertEqual(layout.word(at: first.center)?.id, first.id)

        let padded = CGPoint(x: first.rect.maxX + 3, y: first.rect.midY)
        XCTAssertEqual(layout.word(at: padded)?.id, first.id, "hit testing adds a small halo")
        XCTAssertNil(layout.word(at: CGPoint(x: -50, y: -50)))
    }

    func testHitTestingPrefersTheSmallestContainingWord() {
        let big = cloudWord(id: "big", rect: CGRect(x: 0, y: 0, width: 200, height: 100))
        let small = cloudWord(id: "small", rect: CGRect(x: 40, y: 30, width: 40, height: 20))
        let layout = WordCloudLayout(words: [big, small], size: CGSize(width: 400, height: 300))
        XCTAssertEqual(layout.word(at: CGPoint(x: 50, y: 40))?.id, "small")
        XCTAssertEqual(layout.word(at: CGPoint(x: 10, y: 10))?.id, "big")
    }

    func testMeasurementScalesWithTextLength() {
        let short = WordCloudLayout.measure("S", font: 20)
        let long = WordCloudLayout.measure("SwiftUI", font: 20)
        XCTAssertGreaterThan(long.width, short.width)
        XCTAssertGreaterThan(short.height, 0)
        XCTAssertGreaterThan(long.height, 0)
    }

    func testLayoutIsDeterministic() {
        let graph = tagGraph()
        let first = WordCloudLayout.make(graph: graph, size: CGSize(width: 900, height: 600))
        let second = WordCloudLayout.make(graph: graph, size: CGSize(width: 900, height: 600))
        XCTAssertEqual(first.words.map(\.id), second.words.map(\.id))
        XCTAssertEqual(first.words.map(\.rect), second.words.map(\.rect))
    }
}

// MARK: - Hybrid cloud

final class HybridWordLayoutTests: XCTestCase {

    private func projection(size: CGSize) -> MapProjection {
        let graph = tagGraph()
        return MapProjection(
            camera: .identity,
            camera3D: Camera3D(),
            modeBlend: 0,
            size: size,
            positions2D: GraphLayout.anchors(for: graph),
            positions3D: GraphLayout3D.anchors(for: graph)
        )
    }

    func testEmptyAndSmallLayouts() {
        let cache = HybridLayoutCache()
        let size = CGSize(width: 60, height: 60)
        XCTAssertTrue(
            cache.layout(
                graph: tagGraph(),
                graphRevision: 1,
                projection: projection(size: size),
                size: size,
                positionEpoch: 0
            ).words.isEmpty
        )

        let large = CGSize(width: 900, height: 600)
        XCTAssertTrue(
            cache.layout(
                graph: tagGraph(includeTags: false),
                graphRevision: 2,
                projection: projection(size: large),
                size: large,
                positionEpoch: 0
            ).words.isEmpty
        )
    }

    func testWordsAreAnchoredInsideTheCanvasAndDoNotOverlap() {
        let size = CGSize(width: 900, height: 600)
        let graph = tagGraph()
        let cache = HybridLayoutCache()
        let layout = cache.layout(
            graph: graph,
            graphRevision: 1,
            projection: projection(size: size),
            size: size,
            positionEpoch: 0
        )
        XCTAssertFalse(layout.words.isEmpty)
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
        for word in layout.words {
            XCTAssertTrue(bounds.contains(word.rect), "\(word.term) escapes the canvas")
            XCTAssertGreaterThan(word.fontSize, 0)
        }
        for i in layout.words.indices {
            for j in layout.words.indices where j > i {
                XCTAssertFalse(layout.words[i].rect.intersects(layout.words[j].rect))
            }
        }
    }

    func testCacheReturnsStableLayoutForTheSameProjection() {
        let size = CGSize(width: 900, height: 600)
        let graph = tagGraph()
        let cache = HybridLayoutCache()
        let projection = projection(size: size)
        let first = cache.layout(graph: graph, graphRevision: 1, projection: projection, size: size, positionEpoch: 0)
        let second = cache.layout(graph: graph, graphRevision: 1, projection: projection, size: size, positionEpoch: 0)
        XCTAssertEqual(first.words.map(\.id), second.words.map(\.id))
        XCTAssertEqual(first.words.map(\.rect), second.words.map(\.rect))

        let moved = cache.layout(graph: graph, graphRevision: 1, projection: projection, size: size, positionEpoch: 1)
        XCTAssertEqual(first.words.map(\.id), moved.words.map(\.id))
    }

    func testChangingGraphRevisionRebuildsSeeds() {
        let size = CGSize(width: 900, height: 600)
        let cache = HybridLayoutCache()
        _ = cache.layout(
            graph: tagGraph(),
            graphRevision: 1,
            projection: projection(size: size),
            size: size,
            positionEpoch: 0
        )
        let other = GraphBuilder.build(
            library: ThreadLibrary(threads: [
                ConversationThread(
                    id: "only",
                    provider: .claude,
                    title: "Only",
                    createdAt: Date(timeIntervalSince1970: 0),
                    messages: [ChatMessage(id: "m", role: .user, text: "singular term")]
                )
            ]),
            filters: .default
        )
        let layout = cache.layout(
            graph: other,
            graphRevision: 2,
            projection: projection(size: size),
            size: size,
            positionEpoch: 0
        )
        XCTAssertTrue(layout.words.isEmpty, "a single thread has no shared tags")
    }

    func testHitTestingPrefersTheSmallestWord() {
        let big = cloudWord(id: "big", rect: CGRect(x: 0, y: 0, width: 200, height: 100))
        let small = cloudWord(id: "small", rect: CGRect(x: 40, y: 30, width: 40, height: 20))
        let layout = HybridWordLayout(words: [big, small], size: CGSize(width: 400, height: 300))
        XCTAssertEqual(layout.word(at: CGPoint(x: 50, y: 40))?.id, "small")
        XCTAssertEqual(layout.word(at: CGPoint(x: 10, y: 10))?.id, "big")
        XCTAssertNil(layout.word(at: CGPoint(x: 500, y: 500)))
    }
}
