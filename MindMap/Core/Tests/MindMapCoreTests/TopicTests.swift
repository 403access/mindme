import XCTest
@testable import MindMapCore

final class TopicTests: XCTestCase {

    // MARK: - Fixtures

    private func thread(
        id: String,
        title: String,
        exchanges: [(String, String)],
        start: Date = Date(timeIntervalSince1970: 1_780_000_000)
    ) -> ConversationThread {
        var messages: [ChatMessage] = []
        for (offset, exchange) in exchanges.enumerated() {
            let date = start.addingTimeInterval(Double(offset) * 600)
            messages.append(ChatMessage(
                id: "\(id)-u\(offset)",
                role: .user,
                text: exchange.0,
                timestamp: date
            ))
            messages.append(ChatMessage(
                id: "\(id)-a\(offset)",
                role: .assistant,
                text: exchange.1,
                timestamp: date.addingTimeInterval(30)
            ))
        }
        return ConversationThread(
            id: id,
            provider: .chatgpt,
            title: title,
            createdAt: start,
            messages: messages
        )
    }

    private func techThread() -> ConversationThread {
        thread(
            id: "tech",
            title: "Database migration for the Swift API",
            exchanges: [
                ("The Swift API endpoint fails after the database schema migration. I need to debug the backend and compile a fix.",
                 "Check the migration, inspect the query, and read the server logs. Refactor the endpoint and add a test."),
                ("The server still returns an error when the schema is migrated. Which database function should I change?",
                 "Trace the SQL query, then update the migration and rerun the test suite.")
            ]
        )
    }

    private func legalThread() -> ConversationThread {
        thread(
            id: "legal",
            title: "NDA and liability review",
            exchanges: [
                ("Please review the contract clause about liability and the NDA. The termination terms and jurisdiction look wrong.",
                 "The agreement's indemnity clause and breach terms need counsel; check the signature block."),
                ("Can the contract limit liability for the vendor and still keep the NDA enforceable?",
                 "A clause can cap liability, but the agreement must state the jurisdiction and termination terms clearly.")
            ]
        )
    }

    private func productThread() -> ConversationThread {
        thread(
            id: "product",
            title: "Pricing and roadmap for launch",
            exchanges: [
                ("We need to prioritize the roadmap, scope the MVP, and decide pricing packaging for the subscription tier before launch.",
                 "Interview customers, validate the persona, and align the milestone with the pricing plan."),
                ("Which customer segment should we target first, and how should the subscription tier be packaged?",
                 "Start with the segment that has the clearest feedback, then test the pricing with a small launch.")
            ]
        )
    }

    private func philosophyThread() -> ConversationThread {
        thread(
            id: "phil",
            title: "Modal logic and the metaphysics of possible worlds",
            exchanges: [
                ("Can you explain Kripke semantics for modal logic? I want to understand rigid designation, possible worlds, necessity, and the quantifier rules in quantified modal logic.",
                 "Kripke semantics interprets necessity with an accessibility relation between possible worlds. A rigid designator picks the same individual in every world, while a definite description may not. Quantified modal logic adds the Barcan formula and requires deciding whether domains vary across worlds."),
                ("How does that connect to the analytic-synthetic distinction and epistemic justification? Is the necessary always a priori?",
                 "Kant tied the a priori to necessity, but Kripke separates the epistemic from the metaphysical: the standard metre is contingent a priori, while water is H2O necessarily a posteriori.")
            ]
        )
    }

    private func mixedProjectThread() -> ConversationThread {        thread(
            id: "mixed",
            title: "Project notes",
            exchanges: [
                ("The Swift API endpoint fails after the database schema migration. I need to debug the backend and compile a fix.",
                 "Check the migration, inspect the query, and read the server logs."),
                ("The server still returns an error when the schema is migrated. Which database function should I change?",
                 "Trace the SQL query, then update the migration and rerun the test suite."),
                ("Now let's switch to the contract and the NDA. The liability clause needs review before we continue.",
                 "The agreement's indemnity clause and termination terms need counsel; check the jurisdiction."),
                ("Can the contract limit liability for the vendor and still keep the NDA enforceable?",
                 "A clause can cap liability, but the agreement must state the jurisdiction and termination terms.")
            ]
        )
    }

    // MARK: - Taxonomy

    func testDefaultTaxonomyIsHierarchical() {
        let taxonomy = TopicTaxonomy.default
        XCTAssertGreaterThanOrEqual(taxonomy.roots.count, 8)
        XCTAssertTrue(taxonomy.nodes.allSatisfy { node in
            node.parentID == nil || taxonomy.node(id: node.parentID) != nil
        })
        XCTAssertNotNil(taxonomy.fallbackLeaf)

        for root in taxonomy.roots {
            XCTAssertFalse(taxonomy.children(of: root.id).isEmpty, "\(root.id) should own sub-regions")
        }
        XCTAssertEqual(taxonomy.path(to: "technology/software").map(\.id), ["technology", "technology/software"])
    }

    // MARK: - Embedding

    func testHashingEmbedderIsDeterministicAndNormalized() {
        let embedder = HashingEmbedder()
        let a = embedder.embed("Swift database migration and schema")
        let b = embedder.embed("Swift database migration and schema")
        XCTAssertEqual(a, b)
        let norm = sqrt(a.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1, accuracy: 0.0001)
        let unrelated = embedder.embed("contract liability NDA")
        XCTAssertLessThan(TopicVector.dot(a, unrelated), TopicVector.dot(a, b))
    }

    // MARK: - Classification

    func testDomainsAreClassifiedAtRegionLevel() {
        let pipeline = TopicPipeline()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let cases: [(ConversationThread, String)] = [
            (techThread(), "technology"),
            (legalThread(), "legal"),
            (productThread(), "product")
        ]
        for (thread, expected) in cases {
            let profile = pipeline.analyze(thread, now: now)
            XCTAssertEqual(profile.primaryRegionID, expected, "\(thread.title) → \(profile.regions.map { "\($0.topicID):\($0.share)" })")
            XCTAssertFalse(profile.segments.isEmpty)
            XCTAssertGreaterThan(profile.regions.first?.share ?? 0, 0.5)
        }
    }

    func testFormalPhilosophyClassifiesIntoPhilosophySpine() {
        let profile = TopicPipeline().analyze(philosophyThread())
        XCTAssertEqual(
            profile.primaryRegionID,
            "philosophy",
            "\(profile.regions.map { "\($0.topicID):\($0.share)" })"
        )
        XCTAssertTrue(
            [
                "philosophy/logic",
                "philosophy/language",
                "philosophy/metaphysics",
                "philosophy/epistemology"
            ].contains(profile.primaryTopicID),
            "unexpected leaf: \(profile.primaryTopicID)"
        )
        XCTAssertTrue(profile.belongs(toRoot: "philosophy", threshold: 0.5))
        XCTAssertFalse(profile.belongs(toRoot: "technology", threshold: 0.5))
    }

    func testSegmentsSplitWhenTopicShifts() {        let thread = mixedProjectThread()
        let segments = ConversationSegmenter().segment(thread)
        XCTAssertGreaterThanOrEqual(segments.count, 2)

        let pipeline = TopicPipeline()
        let profile = pipeline.analyze(thread)
        let regions = Set(profile.segments.map(\.regionID))
        XCTAssertTrue(regions.contains("technology"), "\(profile.segments.map { "\($0.regionID)/\($0.topicID)" })")
        XCTAssertTrue(regions.contains("legal"), "\(profile.segments.map { "\($0.regionID)/\($0.topicID)" })")
        XCTAssertEqual(profile.primaryRegionID, "technology")

        // Segments are contiguous and cover the transcript once.
        XCTAssertEqual(profile.segments.first?.startMessageIndex, 0)
        XCTAssertEqual(profile.segments.last?.endMessageIndex, thread.messages.count)
        for index in 1..<profile.segments.count {
            XCTAssertEqual(profile.segments[index - 1].endMessageIndex, profile.segments[index].startMessageIndex)
        }
    }

    func testSpendFollowsSegmentsAndRegions() {
        var thread = mixedProjectThread()
        thread.cost = 1.5
        // Assistant replies carry OpenCode-style per-message cost.
        thread.messages[1].cost = 0.75
        thread.messages[5].cost = 0.75

        let profile = TopicPipeline().analyze(thread)
        XCTAssertEqual(profile.totalCost, 1.5, accuracy: 0.0001)
        XCTAssertEqual(profile.segments.reduce(0) { $0 + $1.cost }, 1.5, accuracy: 0.0001)

        let technology = try! XCTUnwrap(profile.regions.first { $0.topicID == "technology" })
        let legal = try! XCTUnwrap(profile.regions.first { $0.topicID == "legal" })
        XCTAssertEqual(technology.cost + legal.cost, 1.5, accuracy: 0.0001)
        XCTAssertGreaterThan(technology.cost, 0)
        XCTAssertGreaterThan(legal.cost, 0)

        var filters = GraphFilters.default
        filters.grouping = .region
        let library = ThreadLibrary(threads: [thread])
        let graph = GraphBuilder.build(library: library, filters: filters, topicAnalysis: TopicPipeline().analyze(library))
        XCTAssertEqual(graph.stats.totalCost, 1.5, accuracy: 0.0001)
        XCTAssertEqual(graph.stats.costThreadCount, 1)
        XCTAssertEqual(graph.threadNodes.first?.cost ?? 0, 1.5, accuracy: 0.0001)
        let regionRoots = graph.groupNodes.filter { $0.parentID == nil }
        XCTAssertEqual(regionRoots.reduce(0) { $0 + $1.cost }, 1.5, accuracy: 0.0001)
        XCTAssertTrue(graph.groupNodes.contains { $0.parentID != nil && $0.cost > 0 })
    }

    func testSessionCostRescalesTrimmedSegmentCosts() {
        var thread = mixedProjectThread()
        thread.cost = 3.0
        // Only two visible assistant messages carry 0.25 each; the session
        // total says 3.0 because many messages were trimmed on import.
        thread.messages[1].cost = 0.25
        thread.messages[5].cost = 0.25

        let profile = TopicPipeline().analyze(thread)
        XCTAssertEqual(profile.totalCost, 3.0, accuracy: 0.0001)
        XCTAssertEqual(profile.segments.reduce(0) { $0 + $1.cost }, 3.0, accuracy: 0.0001)
    }

    func testLowConfidenceFallsBackToEmerging() {
        let thread = thread(
            id: "vague",
            title: "Random musing",
            exchanges: [("Hmm, interesting. Tell me more about that, please.", "Sure.")]
        )
        let profile = TopicPipeline().analyze(thread)
        XCTAssertEqual(profile.primaryRegionID, "emerging")
    }

    // MARK: - Pipeline

    func testPipelineIsDeterministic() {
        let library = ThreadLibrary(threads: [techThread(), legalThread(), productThread()])
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let first = TopicPipeline().analyze(library, now: now)
        let second = TopicPipeline().analyze(library, now: now)

        XCTAssertEqual(first.libraryHash, second.libraryHash)
        for id in first.profiles.keys {
            XCTAssertEqual(first.profiles[id]?.segments.map(\.topicID), second.profiles[id]?.segments.map(\.topicID))
            XCTAssertEqual(first.profiles[id]?.regions, second.profiles[id]?.regions)
        }
    }

    func testCachedProfilesAreReused() {
        let library = ThreadLibrary(threads: [techThread(), legalThread()])
        let firstDate = Date(timeIntervalSince1970: 1_780_000_000)
        let first = TopicPipeline().analyze(library, now: firstDate)
        let secondDate = firstDate.addingTimeInterval(3_600)
        let second = TopicPipeline().analyze(library, cached: first, now: secondDate)

        XCTAssertEqual(second.libraryHash, first.libraryHash)
        XCTAssertEqual(second.profiles["tech"]?.analyzedAt, firstDate)
        XCTAssertEqual(second.updatedAt, secondDate)
    }

    func testContentHashChangesWithText() {
        let original = techThread()
        var changed = original
        changed.messages[0].text += " New detail about Kubernetes."
        XCTAssertNotEqual(
            TopicPipeline.contentHash(for: original),
            TopicPipeline.contentHash(for: changed)
        )
    }

    // MARK: - Graph

    func testRegionGroupingBuildsHierarchy() {
        let library = ThreadLibrary(threads: [techThread(), legalThread(), productThread()])
        var filters = GraphFilters.default
        filters.grouping = .region
        let analysis = TopicPipeline().analyze(library)
        let graph = GraphBuilder.build(library: library, filters: filters, topicAnalysis: analysis)

        let roots = graph.groupNodes.filter { $0.parentID == nil }
        let subregions = graph.groupNodes.filter { $0.parentID != nil }
        XCTAssertGreaterThanOrEqual(roots.count, 3)
        XCTAssertGreaterThanOrEqual(subregions.count, 3)

        for subregion in subregions {
            XCTAssertNotNil(graph.node(id: subregion.parentID))
            XCTAssertEqual(graph.node(id: subregion.parentID)?.kind, .group)
        }

        // One thread node per conversation, each attached to a sub-region.
        XCTAssertEqual(graph.threadNodes.count, 3)
        XCTAssertEqual(Set(graph.threadNodes.compactMap(\.threadID)).count, 3)
        for node in graph.threadNodes {
            let group = graph.node(id: node.groupID)
            XCTAssertNotNil(group)
            XCTAssertNotNil(group?.parentID)
        }

        // Hierarchy edges exist and connect real nodes.
        XCTAssertTrue(graph.edges.contains { $0.kind == .regionGroup })
        let ids = Set(graph.nodes.map(\.id))
        for edge in graph.edges {
            XCTAssertTrue(ids.contains(edge.source))
            XCTAssertTrue(ids.contains(edge.target))
        }

        // Focusing a region lights up its children and threads.
        let region = try! XCTUnwrap(roots.first)
        let path = graph.focusPath(for: region.id)
        XCTAssertTrue(path.contains(region.id))
        XCTAssertTrue(graph.descendantGroupIDs(of: region.id).count > 1)
    }

    func testDemoArchiveProducesRegionHierarchy() {
        let demo = DemoData.make(now: Date(timeIntervalSince1970: 1_780_000_000))
        var filters = GraphFilters.default
        filters.grouping = .region
        let graph = GraphBuilder.build(library: demo, filters: filters)

        let roots = graph.groupNodes.filter { $0.parentID == nil }
        XCTAssertGreaterThanOrEqual(roots.count, 6, "demo regions: \(roots.map(\.label))")
        XCTAssertLessThanOrEqual(roots.count, 10)
        for root in roots {
            XCTAssertFalse(graph.childGroups(of: root.id).isEmpty, "\(root.label) has no sub-regions")
        }
        XCTAssertTrue(graph.threadNodes.allSatisfy { graph.node(id: $0.groupID)?.parentID != nil })
    }

    func testRegionGroupingHandlesEmptyAnalysisInline() {
        let library = ThreadLibrary(threads: [techThread(), legalThread()])
        var filters = GraphFilters.default
        filters.grouping = .region
        let graph = GraphBuilder.build(library: library, filters: filters)
        XCTAssertEqual(graph.threadNodes.count, 2)
        XCTAssertFalse(graph.groupNodes.filter { $0.parentID != nil }.isEmpty)
    }

    func testRegionLayoutsStayFiniteAndDeterministic() {
        let demo = DemoData.make(now: Date(timeIntervalSince1970: 1_780_000_000))
        var filters = GraphFilters.default
        filters.grouping = .region
        let graph = GraphBuilder.build(library: demo, filters: filters)

        let anchors = GraphLayout.anchors(for: graph)
        XCTAssertEqual(anchors.count, graph.nodes.count)
        XCTAssertEqual(anchors, GraphLayout.anchors(for: graph))
        for node in graph.nodes {
            let point = try! XCTUnwrap(anchors[node.id])
            XCTAssertTrue(point.x.isFinite)
            XCTAssertTrue(point.y.isFinite)
        }

        let spatial = GraphLayout3D.anchors(for: graph)
        XCTAssertEqual(spatial.count, graph.nodes.count)
        for node in graph.nodes {
            let point = try! XCTUnwrap(spatial[node.id])
            XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite)
        }

        var layout = ForceLayout(graph: graph, anchors: anchors)
        for _ in 0..<120 {
            layout.step(dt: 1.0 / 60.0)
        }
        for body in layout.bodies {
            XCTAssertTrue(body.position.x.isFinite)
            XCTAssertTrue(body.position.y.isFinite)
        }
    }

    // MARK: - Storage

    func testTopicStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapTopics-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TopicStore(directory: directory)
        XCTAssertFalse(store.exists)
        let analysis = TopicPipeline().analyze(ThreadLibrary(threads: [techThread()]))
        try store.save(analysis)
        let loaded = try store.load()
        XCTAssertEqual(loaded.libraryHash, analysis.libraryHash)
        XCTAssertEqual(loaded.profiles["tech"]?.primaryRegionID, "technology")
        XCTAssertEqual(loaded.taxonomy.version, analysis.taxonomy.version)
    }

    func testTaxonomyFileIsSeededAndNeverOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapTaxonomy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TopicStore(directory: directory)
        XCTAssertNil(store.loadTaxonomy())
        store.ensureTaxonomyFile()
        XCTAssertNotNil(store.loadTaxonomy())

        var custom = TopicTaxonomy.default
        custom.nodes[0].label = "Custom Region"
        try store.saveTaxonomy(custom)
        store.ensureTaxonomyFile()
        XCTAssertEqual(store.loadTaxonomy()?.nodes[0].label, "Custom Region")
    }
}
