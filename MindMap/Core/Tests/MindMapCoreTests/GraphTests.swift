import XCTest
@testable import MindMapCore

final class GraphTests: XCTestCase {

    private func library() -> ThreadLibrary {
        var threads: [ConversationThread] = []
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        for index in 0..<12 {
            let provider: Provider = [.chatgpt, .gemini, .claude, .other][index % 4]
            let topic = index % 3 == 0
                ? "SwiftUI canvas performance"
                : (index % 3 == 1 ? "Learning Japanese kanji" : "Marathon training plan")
            let messages = [
                ChatMessage(
                    id: "u\(index)",
                    role: .user,
                    text: "\(topic): how do I make progress? I care about \(topic.lowercased()) and consistency.",
                    timestamp: now.addingTimeInterval(Double(index) * 86_400)
                ),
                ChatMessage(
                    id: "a\(index)",
                    role: .assistant,
                    text: "For \(topic.lowercased()), start small and measure the bottleneck.",
                    timestamp: now.addingTimeInterval(Double(index) * 86_400 + 60)
                )
            ]
            threads.append(ConversationThread(
                id: "\(provider.rawValue)-\(index)",
                provider: provider,
                title: "\(topic) notes \(index)",
                createdAt: now.addingTimeInterval(Double(index) * 86_400),
                messages: messages,
                model: "test-model"
            ))
        }
        return ThreadLibrary(threads: threads)
    }

    func testProviderGroupingAndFilters() {
        let lib = library()
        var filters = GraphFilters.default
        filters.providers = [.chatgpt, .gemini]
        let graph = GraphBuilder.build(library: lib, filters: filters)

        XCTAssertEqual(graph.stats.threadCount, 6)
        XCTAssertEqual(graph.groupNodes.count, 2)
        XCTAssertEqual(graph.stats.groupCount, 2)
        XCTAssertTrue(graph.nodes.allSatisfy { $0.provider != .claude })
        XCTAssertEqual(graph.nodes.filter { $0.kind == .group }.count, 2)
        XCTAssertNotNil(graph.rootNode)

        // Every thread edge connects a real group and a real thread.
        let nodeIDs = Set(graph.nodes.map(\.id))
        for edge in graph.edges {
            XCTAssertTrue(nodeIDs.contains(edge.source))
            XCTAssertTrue(nodeIDs.contains(edge.target))
        }
    }

    func testSearchFilter() {
        let lib = library()
        var filters = GraphFilters.default
        filters.searchText = "kanji"
        let graph = GraphBuilder.build(library: lib, filters: filters)
        XCTAssertGreaterThan(graph.stats.threadCount, 0)
        XCTAssertEqual(graph.stats.threadCount, 4)
        XCTAssertTrue(graph.threadNodes.allSatisfy { $0.label.lowercased().contains("kanji") })
    }

    func testSinceFilter() {
        let lib = library()
        var filters = GraphFilters.default
        let cutoff = lib.threads.map(\.updatedAt).sorted()[6]
        filters.since = cutoff
        let graph = GraphBuilder.build(library: lib, filters: filters)
        XCTAssertLessThanOrEqual(graph.stats.threadCount, 6)
        XCTAssertTrue(graph.stats.threadCount > 0)
    }

    func testTopicGroupingProducesClusters() {
        let lib = library()
        var filters = GraphFilters.default
        filters.grouping = .topic
        let graph = GraphBuilder.build(library: lib, filters: filters)

        XCTAssertGreaterThanOrEqual(graph.groupNodes.count, 2)
        // Group labels are topic words, not provider names.
        let labels = Set(graph.groupNodes.map(\.label))
        XCTAssertFalse(labels.contains("CHATGPT"))
        // All threads still belong to exactly one group.
        for node in graph.threadNodes {
            XCTAssertNotNil(node.groupID)
        }
    }

    func testTagGraph() {
        let lib = library()
        let graph = GraphBuilder.build(library: lib, filters: .default)
        XCTAssertGreaterThan(graph.tagNodes.count, 0)
        // Tags merge across providers: at least one tag connects multiple threads.
        let adjacency = graph.adjacency
        let shared = graph.tagNodes.contains { tag in
            let threads = (adjacency[tag.id] ?? []).filter { $0.hasPrefix("thread:") }
            return threads.count >= 2
        }
        XCTAssertTrue(shared)
    }

    func testEmptyGraph() {
        var filters = GraphFilters.default
        filters.providers = []
        let graph = GraphBuilder.build(library: library(), filters: filters)
        XCTAssertTrue(graph.isEmpty)
        XCTAssertEqual(graph.nodes.count, 1)
        XCTAssertEqual(graph.nodes.first?.kind, .root)
    }

    func testFocusPath() {
        let graph = GraphBuilder.build(library: library(), filters: .default)
        let thread = try! XCTUnwrap(graph.threadNodes.first)
        let path = graph.focusPath(for: thread.id)
        XCTAssertTrue(path.contains(thread.id))
        XCTAssertTrue(path.contains("root"))
        XCTAssertTrue(path.contains(thread.groupID!))

        let tagID = (graph.adjacency[thread.id] ?? []).first { $0.hasPrefix("tag:") }
        if let tagID {
            XCTAssertTrue(path.contains(tagID))
        }
    }

    func testDemoDataShape() {
        let demo = DemoData.make(now: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertGreaterThan(demo.threads.count, 60)
        XCTAssertEqual(demo.providerCounts[.chatgpt] ?? 0, demo.providerCounts[.gemini] ?? 0)
        XCTAssertTrue(demo.threads.allSatisfy(\.isDemo))
        XCTAssertTrue(demo.threads.allSatisfy { $0.messages.count >= 4 })

        let graph = GraphBuilder.build(library: demo, filters: .default)
        XCTAssertGreaterThan(graph.stats.threadCount, 60)
        XCTAssertGreaterThan(graph.stats.tagCount, 8)
        XCTAssertGreaterThanOrEqual(graph.stats.groupCount, 3)
    }
}

final class LayoutTests: XCTestCase {

    func testAnchorsAndSimulationRemainFinite() {
        let demo = DemoData.make(now: Date(timeIntervalSince1970: 1_780_000_000))
        let graph = GraphBuilder.build(library: demo, filters: .default)
        let anchors = GraphLayout.anchors(for: graph)

        XCTAssertEqual(anchors.count, graph.nodes.count)
        for node in graph.nodes {
            let anchor = try! XCTUnwrap(anchors[node.id])
            XCTAssertTrue(anchor.length.isFinite)
            if node.kind != .root {
                XCTAssertGreaterThan(anchor.length, 0)
            }
        }

        var layout = ForceLayout(graph: graph, anchors: anchors)
        for _ in 0..<300 {
            layout.step(dt: 1.0 / 60.0)
        }
        for body in layout.bodies {
            XCTAssertTrue(body.position.x.isFinite)
            XCTAssertTrue(body.position.y.isFinite)
            XCTAssertLessThan(body.position.length, 10_000)
        }
        // Root stays fixed and velocities stay bounded.
        XCTAssertEqual(layout.bodies.first { $0.kind == .root }?.position, .zero)
        XCTAssertEqual(layout.steps, 300)
        for body in layout.bodies {
            XCTAssertLessThan(body.velocity.length, 600)
        }
    }

    func testSpatialLayoutIsFiniteAndDeterministic() {
        let demo = DemoData.make(now: Date(timeIntervalSince1970: 1_780_000_000))
        let graph = GraphBuilder.build(library: demo, filters: .default)
        let anchors = GraphLayout3D.anchors(for: graph)
        XCTAssertEqual(anchors.count, graph.nodes.count)
        XCTAssertEqual(anchors["root"], .zero)

        var zValues = Set<Int>()
        for node in graph.nodes {
            let anchor = try! XCTUnwrap(anchors[node.id])
            XCTAssertTrue(anchor.x.isFinite)
            XCTAssertTrue(anchor.y.isFinite)
            XCTAssertTrue(anchor.z.isFinite)
            if node.kind != .root {
                XCTAssertGreaterThan(anchor.length, 20)
            }
            zValues.insert(Int(anchor.z.rounded()))
        }
        XCTAssertGreaterThan(zValues.count, 4)
        XCTAssertEqual(anchors, GraphLayout3D.anchors(for: graph))
    }

    func testLayoutIsDeterministic() {
        let demo = DemoData.make(now: Date(timeIntervalSince1970: 1_780_000_000))
        let graph = GraphBuilder.build(library: demo, filters: .default)
        let first = GraphLayout.anchors(for: graph)
        let second = GraphLayout.anchors(for: graph)
        XCTAssertEqual(first, second)
    }
}

final class KeywordTests: XCTestCase {

    func testStopwordsAndTokens() {
        XCTAssertEqual(KeywordExtractor.tokenize("The model and the agent"), ["agent"])
        XCTAssertEqual(KeywordExtractor.tokenize("SwiftUI Canvas performance"), ["swiftui", "canvas", "performance"])
        XCTAssertFalse(KeywordExtractor.tokenize("123 456 !!!").contains("123"))
    }

    func testKeywordsFavorTitleAndTopics() {
        let thread = ConversationThread(
            id: "t",
            provider: .chatgpt,
            title: "Rust ownership and borrowing",
            createdAt: Date(),
            messages: [
                ChatMessage(id: "1", role: .user, text: "How does borrowing work in Rust with ownership?"),
                ChatMessage(id: "2", role: .assistant, text: "Ownership is checked by the borrow checker. Borrowing grants references.")
            ]
        )
        let index = KeywordExtractor.buildIndex(threads: [thread])
        let keywords = index.keywords(for: "t")
        XCTAssertTrue(keywords.prefix(4).map(\.term).contains("borrowing"))
        XCTAssertTrue(keywords.prefix(4).map(\.term).contains("ownership"))
    }

    func testStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ThreadStore(directory: directory)
        XCTAssertFalse(store.exists)

        var library = DemoData.make(now: Date(timeIntervalSince1970: 1_780_000_000))
        library.threads = Array(library.threads.prefix(3))
        try store.save(library)

        let loaded = try store.load()
        XCTAssertEqual(loaded.threads.count, 3)
        XCTAssertEqual(loaded.threads.first?.title, library.threads.first?.title)
        XCTAssertEqual(loaded.threads.first?.messages.count, library.threads.first?.messages.count)

        var merged = loaded
        let added = merged.merge([
            ConversationThread(id: "external-1", provider: .other, title: "New", createdAt: Date(), messages: [])
        ])
        XCTAssertEqual(added.added, 1)
        XCTAssertEqual(merged.threads.count, 4)
    }
}
