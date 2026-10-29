import XCTest
@testable import MindMapCore

// MARK: - Thread store

final class ThreadStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapStore-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func thread(id: String, updatedAt: TimeInterval, isDemo: Bool = false) -> ConversationThread {
        ConversationThread(
            id: id,
            provider: .chatgpt,
            title: id,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000 + updatedAt),
            messages: [ChatMessage(id: "\(id)-m", role: .user, text: "hello")],
            isDemo: isDemo
        )
    }

    func testDefaultLocation() {
        let store = ThreadStore()
        XCTAssertEqual(store.directory.lastPathComponent, "MindMap")
        XCTAssertEqual(store.libraryURL.lastPathComponent, "library.json")
        XCTAssertEqual(store.libraryURL.deletingLastPathComponent(), store.directory)
    }

    func testCustomLocationAndMissingLibrary() throws {
        let store = ThreadStore(directory: directory)
        XCTAssertEqual(store.directory, directory)
        XCTAssertFalse(store.exists)
        XCTAssertEqual(try store.load().threads.count, 0)
        XCTAssertNil(try store.load().lastImport)
    }

    func testSaveCreatesDirectoryAndLoadSortsByRecency() throws {
        let store = ThreadStore(directory: directory.appendingPathComponent("nested/deeper"))
        var library = ThreadLibrary(
            threads: [
                thread(id: "old", updatedAt: 100),
                thread(id: "new", updatedAt: 300),
                thread(id: "middle", updatedAt: 200)
            ],
            lastImport: Date(timeIntervalSince1970: 1_780_000_500)
        )
        try store.save(library)
        XCTAssertTrue(store.exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.path))

        let loaded = try store.load()
        XCTAssertEqual(loaded.threads.map(\.id), ["new", "middle", "old"])
        XCTAssertEqual(loaded.lastImport, library.lastImport)

        // Saving again overwrites the archive.
        library.threads = [thread(id: "only", updatedAt: 1)]
        try store.save(library)
        XCTAssertEqual(try store.load().threads.map(\.id), ["only"])
    }

    func testDemoFlagSurvivesRoundTrip() throws {
        let store = ThreadStore(directory: directory)
        try store.save(ThreadLibrary(threads: [thread(id: "demo", updatedAt: 1, isDemo: true)]))
        XCTAssertTrue(try store.load().hasDemoData)
    }

    func testEmptyFileLoadsAsEmpty() throws {
        let store = ThreadStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: store.libraryURL)
        XCTAssertTrue(try store.load().threads.isEmpty)
    }

    func testMalformedFileThrows() throws {
        let store = ThreadStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.libraryURL)
        XCTAssertThrowsError(try store.load())
    }

    func testDeleteLibrary() throws {
        let store = ThreadStore(directory: directory)
        try store.save(ThreadLibrary(threads: [thread(id: "a", updatedAt: 1)]))
        XCTAssertTrue(store.exists)
        try store.deleteLibrary()
        XCTAssertFalse(store.exists)
        XCTAssertEqual(try store.load().threads.count, 0)
        XCTAssertNoThrow(try store.deleteLibrary(), "deleting a missing library is harmless")
    }
}

// MARK: - Topic store

final class TopicStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapTopicStore-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDefaultLocation() {
        let store = TopicStore()
        XCTAssertEqual(store.directory.lastPathComponent, "MindMap")
        XCTAssertEqual(store.analysisURL.lastPathComponent, "topics.json")
        XCTAssertEqual(store.taxonomyURL.lastPathComponent, "taxonomy.json")
        XCTAssertEqual(store.analysisURL.deletingLastPathComponent(), store.directory)
        XCTAssertEqual(store.taxonomyURL.deletingLastPathComponent(), store.directory)
    }

    func testMissingAndEmptyAnalysis() throws {
        let store = TopicStore(directory: directory)
        XCTAssertFalse(store.exists)
        XCTAssertTrue(try store.load().isEmpty)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: store.analysisURL)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testAnalysisRoundTripAndDelete() throws {
        let store = TopicStore(directory: directory)
        let analysis = TopicAnalysis(
            libraryHash: "abc",
            profiles: [:],
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        try store.save(analysis)
        XCTAssertTrue(store.exists)
        XCTAssertEqual(try store.load().libraryHash, "abc")
        try store.delete()
        XCTAssertFalse(store.exists)
        XCTAssertNoThrow(try store.delete(), "deleting a missing analysis is harmless")
    }

    func testMalformedAnalysisThrows() throws {
        let store = TopicStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.analysisURL)
        XCTAssertThrowsError(try store.load())
    }

    func testTaxonomyRoundTripSeedAndInvalidFile() throws {
        let store = TopicStore(directory: directory)
        XCTAssertNil(store.loadTaxonomy())

        try store.saveTaxonomy(.default)
        let loaded = try XCTUnwrap(store.loadTaxonomy())
        XCTAssertEqual(loaded, .default)

        // ensureTaxonomyFile seeds only when the file is missing.
        try FileManager.default.removeItem(at: store.taxonomyURL)
        store.ensureTaxonomyFile()
        XCTAssertNotNil(store.loadTaxonomy())
        var custom = TopicTaxonomy.default
        custom.nodes[0].label = "Kept"
        try store.saveTaxonomy(custom)
        store.ensureTaxonomyFile()
        XCTAssertEqual(store.loadTaxonomy()?.nodes[0].label, "Kept")

        try Data().write(to: store.taxonomyURL)
        XCTAssertNil(store.loadTaxonomy(), "an empty file is ignored")

        try Data("{not json".utf8).write(to: store.taxonomyURL)
        XCTAssertNil(store.loadTaxonomy(), "malformed taxonomy is ignored")
    }

    func testMergedTaxonomyAddsNewRegionsAndKeepsEdits() throws {
        let store = TopicStore(directory: directory)
        let old = TopicTaxonomy(
            version: 4,
            nodes: [
                TopicNode(id: "technology", label: "Renamed Tech", seeds: ["tech"]),
                TopicNode(id: "emerging", label: "Emerging", isFallback: true)
            ]
        )
        try store.saveTaxonomy(old)

        let merged = store.loadMergedTaxonomy()
        XCTAssertEqual(merged.version, TopicTaxonomy.default.version)
        XCTAssertEqual(merged.node(id: "technology")?.label, "Renamed Tech", "user edits survive")
        XCTAssertNotNil(merged.node(id: "philosophy"), "new regions are folded in")
        XCTAssertNotNil(merged.node(id: "philosophy/logic"))
        XCTAssertEqual(store.loadTaxonomy()?.version, TopicTaxonomy.default.version, "merge is persisted")

        // A current taxonomy is returned untouched.
        let current = store.loadMergedTaxonomy()
        XCTAssertEqual(current, merged)
    }
}

// MARK: - Taxonomy

final class TopicTaxonomyTests: XCTestCase {

    private let taxonomy = TopicTaxonomy(nodes: [
        TopicNode(id: "root", label: "Root", seeds: ["a"]),
        TopicNode(id: "root/child", label: "Child", seeds: ["b"], parentID: "root"),
        TopicNode(id: "root/child/leaf", label: "Leaf", seeds: ["c"], parentID: "root/child"),
        TopicNode(id: "fallback", label: "Fallback", isFallback: true)
    ])

    func testLookupAndStructure() {
        XCTAssertEqual(taxonomy.node(id: "root")?.label, "Root")
        XCTAssertNil(taxonomy.node(id: "missing"))
        XCTAssertNil(taxonomy.node(id: nil))
        XCTAssertEqual(taxonomy.roots.map(\.id), ["root", "fallback"])
        XCTAssertEqual(taxonomy.children(of: "root").map(\.id), ["root/child"])
        XCTAssertEqual(taxonomy.children(of: "root/child").map(\.id), ["root/child/leaf"])
        XCTAssertTrue(taxonomy.children(of: "missing").isEmpty)
        XCTAssertEqual(taxonomy.leaves.map(\.id), ["root/child/leaf"])
        XCTAssertEqual(taxonomy.fallbackLeaf?.id, "fallback")
        XCTAssertEqual(taxonomy.label(for: "root/child"), "Child")
        XCTAssertEqual(taxonomy.label(for: "unknown"), "unknown")
    }

    func testPathFromRootToLeaf() {
        XCTAssertEqual(
            taxonomy.path(to: "root/child/leaf").map(\.id),
            ["root", "root/child", "root/child/leaf"]
        )
        XCTAssertEqual(taxonomy.path(to: "missing"), [])
    }

    func testDefaultTaxonomyIsWellFormed() {
        let value = TopicTaxonomy.default
        XCTAssertGreaterThanOrEqual(value.roots.count, 8)
        XCTAssertEqual(value.version, 5)
        let ids = value.nodes.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "node IDs are unique")
        for node in value.nodes {
            if let parentID = node.parentID {
                XCTAssertNotNil(value.node(id: parentID), "\(node.id) has a valid parent")
            }
            XCTAssertFalse(node.label.isEmpty, node.id)
        }
        XCTAssertNotNil(value.fallbackLeaf)
        XCTAssertEqual(value.fallbackLeaf?.isFallback, true)
        XCTAssertEqual(value.path(to: "technology/software").map(\.id), ["technology", "technology/software"])
        XCTAssertEqual(
            value.children(of: "philosophy").map(\.id),
            [
                "philosophy/logic",
                "philosophy/mathematics",
                "philosophy/language",
                "philosophy/mind",
                "philosophy/epistemology",
                "philosophy/metaphysics",
                "philosophy/science"
            ]
        )
        for root in value.roots where !root.isFallback {
            XCTAssertFalse(value.children(of: root.id).isEmpty, "\(root.id) should own sub-regions")
        }
    }

    func testTaxonomyIsCodable() throws {
        let data = try JSONEncoder().encode(taxonomy)
        XCTAssertEqual(try JSONDecoder().decode(TopicTaxonomy.self, from: data), taxonomy)
    }
}

// MARK: - Demo data

final class DemoDataFeatureTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    func testDemoIsDeterministicForAFixedDate() {
        let first = DemoData.make(now: now)
        let second = DemoData.make(now: now)
        XCTAssertEqual(first.threads.count, second.threads.count)
        XCTAssertEqual(first.threads.map(\.id), second.threads.map(\.id))
        XCTAssertEqual(first.threads.map(\.title), second.threads.map(\.title))
        XCTAssertEqual(first.threads.map(\.createdAt), second.threads.map(\.createdAt))
        XCTAssertEqual(first.threads.map { $0.messages.map(\.id) }, second.threads.map { $0.messages.map(\.id) })
        XCTAssertEqual(first.threads.map { $0.messages.map(\.text) }, second.threads.map { $0.messages.map(\.text) })
    }

    func testDemoShapeAndFlags() {
        let demo = DemoData.make(now: now)
        XCTAssertGreaterThan(demo.threads.count, 60)
        XCTAssertNil(demo.lastImport)
        XCTAssertTrue(demo.hasDemoData)
        XCTAssertEqual(demo.demoThreadCount, demo.threads.count)
        XCTAssertEqual(Set(demo.threads.map(\.id)).count, demo.threads.count)

        let earliestAllowed = now.addingTimeInterval(-471 * 86_400)
        for thread in demo.threads {
            XCTAssertTrue(thread.isDemo)
            XCTAssertEqual(thread.sourceFile, "demo")
            XCTAssertFalse(thread.title.isEmpty)
            XCTAssertNotNil(thread.model)
            XCTAssertGreaterThanOrEqual(thread.messages.count, 4)
            XCTAssertEqual(thread.messages.first?.role, .user)
            XCTAssertEqual(thread.messages.last?.role, .assistant)
            for (index, message) in thread.messages.enumerated() {
                XCTAssertFalse(message.text.isEmpty)
                XCTAssertEqual(message.role, index % 2 == 0 ? .user : .assistant)
                XCTAssertNotNil(message.timestamp)
            }
            XCTAssertLessThanOrEqual(thread.updatedAt.timeIntervalSince1970, now.timeIntervalSince1970 + 1)
            XCTAssertGreaterThanOrEqual(thread.createdAt, earliestAllowed)
            XCTAssertGreaterThanOrEqual(thread.updatedAt, thread.createdAt)
        }
        XCTAssertEqual(demo.threads.map(\.updatedAt), demo.threads.map(\.updatedAt).sorted(by: >), "sorted newest first")
    }

    func testDemoCoversProviders() {
        let demo = DemoData.make(now: now)
        let counts = demo.providerCounts
        XCTAssertGreaterThan(counts[.chatgpt] ?? 0, 0)
        XCTAssertGreaterThan(counts[.gemini] ?? 0, 0)
        XCTAssertGreaterThan(counts[.claude] ?? 0, 0)
        XCTAssertGreaterThan(counts[.other] ?? 0, 0)
        XCTAssertEqual(counts[.chatgpt], counts[.gemini])
    }

    func testDemoBuildsACompleteGraph() {
        let demo = DemoData.make(now: now)
        let graph = GraphBuilder.build(library: demo, filters: .default)
        XCTAssertEqual(graph.stats.threadCount, demo.threads.count)
        XCTAssertEqual(graph.stats.groupCount, demo.providerCounts.count)
        XCTAssertEqual(graph.rootNode?.label, "MINDME")
        XCTAssertGreaterThan(graph.stats.tagCount, 8)
        XCTAssertFalse(graph.hasCostData, "demo data carries no provider spend")
        XCTAssertEqual(graph.stats.totalCost, 0)
        XCTAssertTrue(graph.threadNodes.allSatisfy { $0.provider != nil })
    }

    func testDemoCanBeMergedAndCleared() {
        var library = ThreadLibrary.empty
        let demo = DemoData.make(now: now)
        let result = library.merge(demo.threads)
        XCTAssertEqual(result.added, demo.threads.count)
        XCTAssertEqual(result.updated, 0)
        library.removeDemoData()
        XCTAssertTrue(library.threads.isEmpty)
        XCTAssertFalse(library.hasDemoData)
    }

    func testSplitMixIsDeterministic() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        var other = SplitMix64(seed: 43)
        for _ in 0..<10 {
            XCTAssertEqual(first.next(), second.next())
        }
        var firstAgain = SplitMix64(seed: 42)
        XCTAssertNotEqual(firstAgain.next(), other.next())
    }
}
