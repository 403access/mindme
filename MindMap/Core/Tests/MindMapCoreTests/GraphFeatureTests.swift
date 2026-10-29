import XCTest
@testable import MindMapCore

// MARK: - Filters

final class GraphFiltersTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func thread(
        id: String = "t",
        provider: Provider = .chatgpt,
        title: String = "SwiftUI Canvas performance",
        texts: [String] = ["Performance tuning notes"],
        updatedAt: Date? = nil
    ) -> ConversationThread {
        ConversationThread(
            id: id,
            provider: provider,
            title: title,
            createdAt: start,
            updatedAt: updatedAt,
            messages: texts.enumerated().map { index, text in
                ChatMessage(id: "\(id)-\(index)", role: .user, text: text)
            }
        )
    }

    func testProviderAndDateFilters() {
        let value = thread(updatedAt: start.addingTimeInterval(200))
        XCTAssertTrue(GraphFilters.default.matches(value))

        var filters = GraphFilters.default
        filters.providers = [.gemini]
        XCTAssertFalse(filters.matches(value))

        filters = GraphFilters.default
        filters.since = start.addingTimeInterval(200)
        XCTAssertTrue(filters.matches(value), "boundary is inclusive")
        filters.since = start.addingTimeInterval(201)
        XCTAssertFalse(filters.matches(value))
    }

    func testSearchMatchesTitleBodyAndAllTokens() {
        let value = thread(texts: ["Performance tuning notes"])

        var filters = GraphFilters.default
        filters.searchText = "swiftui"
        XCTAssertTrue(filters.matches(value), "case-insensitive title match")

        filters.searchText = "TUNING"
        XCTAssertTrue(filters.matches(value), "message match")

        filters.searchText = "swiftui tuning"
        XCTAssertTrue(filters.matches(value), "multi-token AND across title and body")

        filters.searchText = "swiftui missing"
        XCTAssertFalse(filters.matches(value))

        filters.searchText = "  swiftui   canvas  "
        XCTAssertTrue(filters.matches(value), "whitespace is collapsed")

        filters.searchText = "tuningx"
        XCTAssertFalse(filters.matches(value))

        filters.searchText = ""
        XCTAssertTrue(filters.matches(value))
    }

    func testGroupingAndNodeKindMetadata() {
        XCTAssertEqual(GroupingMode.allCases.map(\.label), ["PROVIDER", "TOPIC", "REGION", "ERA"])
        XCTAssertEqual(GroupingMode.region.title, "Region")
        XCTAssertEqual(GroupingMode.provider.id, "provider")

        XCTAssertTrue(NodeKind.root.isHub)
        XCTAssertTrue(NodeKind.group.isHub)
        XCTAssertFalse(NodeKind.thread.isHub)
        XCTAssertFalse(NodeKind.tag.isHub)
    }
}

// MARK: - Builder modes and limits

final class GraphBuilderFeatureTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func thread(
        id: String,
        provider: Provider = .chatgpt,
        title: String? = nil,
        texts: [String] = [],
        updatedAt: TimeInterval = 0,
        cost: Double? = nil
    ) -> ConversationThread {
        ConversationThread(
            id: id,
            provider: provider,
            title: title ?? id,
            createdAt: start.addingTimeInterval(updatedAt),
            updatedAt: start.addingTimeInterval(updatedAt),
            messages: texts.enumerated().map { index, text in
                ChatMessage(id: "\(id)-\(index)", role: .user, text: text)
            },
            cost: cost
        )
    }

    func testMaxThreadsKeepsMostRecent() {
        let library = ThreadLibrary(threads: (1...5).map { index in
            thread(id: "t\(index)", updatedAt: TimeInterval(index))
        })
        var filters = GraphFilters.default
        filters.maxThreads = 3
        let graph = GraphBuilder.build(library: library, filters: filters)
        XCTAssertEqual(graph.stats.threadCount, 3)
        XCTAssertEqual(Set(graph.threadNodes.compactMap(\.threadID)), ["t3", "t4", "t5"])
        XCTAssertEqual(graph.stats.unfilteredThreadCount, 5)
    }

    func testZeroMaxThreadsProducesEmptyGraph() {
        let library = ThreadLibrary(threads: [thread(id: "t1", updatedAt: 1)])
        var filters = GraphFilters.default
        filters.maxThreads = 0
        let graph = GraphBuilder.build(library: library, filters: filters)
        XCTAssertTrue(graph.isEmpty)
        XCTAssertEqual(graph.nodes.map(\.kind), [.root])
        XCTAssertEqual(graph.stats.unfilteredThreadCount, 1)
    }

    func testStatsAggregateFilteredThreads() {
        let library = ThreadLibrary(threads: [
            thread(
                id: "a",
                texts: ["12345", "67890"],
                updatedAt: 200,
                cost: nil
            ),
            thread(
                id: "b",
                texts: ["abcde"],
                updatedAt: 300,
                cost: 1.5
            )
        ])
        let graph = GraphBuilder.build(library: library, filters: .default)
        XCTAssertEqual(graph.stats.threadCount, 2)
        XCTAssertEqual(graph.stats.messageCount, 3)
        XCTAssertEqual(graph.stats.characterCount, 15)
        XCTAssertEqual(graph.stats.earliest, start.addingTimeInterval(200))
        XCTAssertEqual(graph.stats.latest, start.addingTimeInterval(300))
        XCTAssertEqual(graph.stats.unfilteredThreadCount, 2)
        XCTAssertEqual(graph.stats.groupCount, 1)
        XCTAssertEqual(graph.stats.totalCost, 1.5, accuracy: 0.0001)
        XCTAssertEqual(graph.stats.costThreadCount, 1)
        XCTAssertTrue(graph.hasCostData)
        XCTAssertEqual(graph.maxThreadCost, 1.5, accuracy: 0.0001)
        XCTAssertEqual(graph.maxGroupCost, 1.5, accuracy: 0.0001)
        XCTAssertEqual(graph.stats.tagCount, graph.tagNodes.count)
        XCTAssertEqual(graph.rootNode?.subtitle, "2 THREADS · 1 CONSTELLATION")
    }

    func testEmptyGraphRootSubtitle() {
        var filters = GraphFilters.default
        filters.providers = []
        let graph = GraphBuilder.build(library: ThreadLibrary(threads: [thread(id: "t")]), filters: filters)
        XCTAssertEqual(graph.rootNode?.subtitle, "NO SIGNAL")
        XCTAssertEqual(graph.groupNodes.count, 0)
        XCTAssertEqual(graph.tagNodes.count, 0)
        XCTAssertFalse(graph.hasCostData)
        XCTAssertEqual(graph.maxGroupCost, 0)
        XCTAssertEqual(graph.maxThreadCost, 0)
    }

    func testTagsCanBeDisabled() {
        let library = ThreadLibrary(threads: [
            thread(id: "a", texts: ["shared keyword"]),
            thread(id: "b", texts: ["shared keyword"])
        ])
        var filters = GraphFilters.default
        filters.includeTags = false
        let graph = GraphBuilder.build(library: library, filters: filters)
        XCTAssertTrue(graph.tagNodes.isEmpty)
        XCTAssertEqual(graph.stats.tagCount, 0)
        XCTAssertFalse(graph.edges.contains { $0.kind == .threadTag })
    }

    func testTopicGroupingFallsBackToMiscellany() throws {
        let library = ThreadLibrary(threads: [
            thread(id: "a", title: "One", texts: ["aardvark"]),
            thread(id: "b", title: "Two", texts: ["zebra"])
        ])
        var filters = GraphFilters.default
        filters.grouping = .topic
        let graph = GraphBuilder.build(library: library, filters: filters)
        let misc = try XCTUnwrap(graph.groupNodes.first { $0.id == "group:topic:misc" })
        XCTAssertEqual(misc.label, "MISCELLANY")
        XCTAssertEqual(misc.subtitle, "2 THREADS")
        XCTAssertEqual(Set(graph.threadNodes.compactMap(\.groupID)), [misc.id])
    }

    private func eraThread(id: String, date: Date) -> ConversationThread {
        ConversationThread(
            id: id,
            provider: .other,
            title: id,
            createdAt: date,
            updatedAt: date,
            messages: []
        )
    }

    func testEraGroupingUsesMonthlyBucketsForShortSpans() {
        let dates = [
            Date(timeIntervalSince1970: 1_767_614_400), // 2026-01-05
            Date(timeIntervalSince1970: 1_768_910_400), // 2026-01-20
            Date(timeIntervalSince1970: 1_773_144_000)  // 2026-03-10
        ]
        let library = ThreadLibrary(threads: dates.enumerated().map { eraThread(id: "t\($0.offset)", date: $0.element) })
        var filters = GraphFilters.default
        filters.grouping = .era
        let graph = GraphBuilder.build(library: library, filters: filters)
        XCTAssertEqual(graph.groupNodes.count, 2)
        let ids = Set(graph.groupNodes.map(\.id))
        XCTAssertTrue(ids.contains("group:era:y2026-m01"))
        XCTAssertTrue(ids.contains("group:era:y2026-m03"))
        XCTAssertEqual(graph.stats.threadCount, 3)
    }

    func testEraGroupingUsesQuarterlyBucketsForMultiYearSpans() {
        let dates = [
            Date(timeIntervalSince1970: 1_707_998_400), // 2024-02-15
            Date(timeIntervalSince1970: 1_723_723_200), // 2024-08-15
            Date(timeIntervalSince1970: 1_747_310_400)  // 2025-05-15
        ]
        let library = ThreadLibrary(threads: dates.enumerated().map { eraThread(id: "t\($0.offset)", date: $0.element) })
        var filters = GraphFilters.default
        filters.grouping = .era
        let graph = GraphBuilder.build(library: library, filters: filters)
        let labels = Set(graph.groupNodes.map(\.label))
        XCTAssertEqual(labels, ["Q1 · 24", "Q3 · 24", "Q2 · 25"])
        XCTAssertEqual(
            Set(graph.groupNodes.map(\.id)),
            ["group:era:y2024-q1", "group:era:y2024-q3", "group:era:y2025-q2"]
        )
    }

    func testEraGroupingUsesYearlyBucketsForLongSpans() {
        let dates = [
            Date(timeIntervalSince1970: 1_434_369_600), // 2015-06-15
            Date(timeIntervalSince1970: 1_560_600_000), // 2019-06-15
            Date(timeIntervalSince1970: 1_686_830_400)  // 2023-06-15
        ]
        let library = ThreadLibrary(threads: dates.enumerated().map { eraThread(id: "t\($0.offset)", date: $0.element) })
        var filters = GraphFilters.default
        filters.grouping = .era
        let graph = GraphBuilder.build(library: library, filters: filters)
        XCTAssertEqual(graph.groupNodes.map(\.label), ["2015", "2019", "2023"])
        XCTAssertEqual(graph.groupNodes.map(\.id), ["group:era:y2015", "group:era:y2019", "group:era:y2023"])
    }

    func testRegionGroupingReparentsOrphanThreadsIntoEmerging() throws {
        let value = thread(id: "orphan", cost: 1)
        let profile = ThreadTopicProfile(
            threadID: "orphan",
            contentHash: "hash",
            segments: [],
            regions: [],
            topics: [],
            primaryRegionID: "nope",
            primaryTopicID: "nope",
            totalCost: 1,
            analyzedAt: start
        )
        let analysis = TopicAnalysis(profiles: ["orphan": profile], updatedAt: start)
        let library = ThreadLibrary(threads: [value])
        var filters = GraphFilters.default
        filters.grouping = .region
        let graph = GraphBuilder.build(library: library, filters: filters, topicAnalysis: analysis)

        let root = try XCTUnwrap(graph.groupNodes.first { $0.id == "region:emerging" })
        let child = try XCTUnwrap(graph.groupNodes.first { $0.id == "region:emerging/misc" })
        XCTAssertEqual(root.label, "EMERGING")
        XCTAssertEqual(child.label, "MISCELLANEOUS")
        XCTAssertEqual(child.parentID, root.id)
        XCTAssertEqual(graph.threadNodes.first?.groupID, child.id)
        XCTAssertEqual(root.cost, 1, accuracy: 0.0001)
        XCTAssertEqual(child.cost, 1, accuracy: 0.0001)
    }

    func testRegionRootWithoutChildrenGetsGeneralSubRegion() throws {        let taxonomy = TopicTaxonomy(nodes: [
            TopicNode(id: "custom", label: "Custom", seeds: ["custom"]),
            TopicNode(id: "emerging", label: "Emerging", isFallback: true)
        ])
        let profile = ThreadTopicProfile(
            threadID: "t",
            contentHash: "hash",
            segments: [],
            regions: [],
            topics: [],
            primaryRegionID: "custom",
            primaryTopicID: "custom",
            analyzedAt: start
        )
        let analysis = TopicAnalysis(
            taxonomy: taxonomy,
            libraryHash: "hash",
            profiles: ["t": profile],
            updatedAt: start
        )
        let library = ThreadLibrary(threads: [thread(id: "t")])
        var filters = GraphFilters.default
        filters.grouping = .region
        let graph = GraphBuilder.build(library: library, filters: filters, topicAnalysis: analysis)

        let root = try XCTUnwrap(graph.groupNodes.first { $0.id == "region:custom" })
        let child = try XCTUnwrap(graph.groupNodes.first { $0.id == "region:custom/general" })
        XCTAssertEqual(root.label, "CUSTOM")
        XCTAssertEqual(child.label, "GENERAL")
        XCTAssertEqual(child.parentID, root.id)
        XCTAssertEqual(child.subtitle, "1 THREAD")
        XCTAssertEqual(graph.threadNodes.first?.groupID, child.id)
        XCTAssertFalse(graph.groupNodes.contains { $0.id == "region:emerging" })
    }

    func testTopicRootScopeFiltersBeforeThreadCapAndRespectsThreshold() throws {
        let philosophy = thread(id: "phil", title: "Modal logic and possible worlds", updatedAt: 10)
        let tech = thread(id: "tech", title: "SwiftUI canvas performance", updatedAt: 20)
        let mixed = thread(id: "mixed", title: "Notes on models", updatedAt: 30)

        func profile(id: String, primary: String, shares: [String: Double]) -> ThreadTopicProfile {
            ThreadTopicProfile(
                threadID: id,
                contentHash: "hash-\(id)",
                segments: [],
                regions: shares.map {
                    TopicShare(topicID: $0.key, label: $0.key.capitalized, share: $0.value)
                },
                topics: [],
                primaryRegionID: primary,
                primaryTopicID: "\(primary)/general",
                analyzedAt: start
            )
        }

        let analysis = TopicAnalysis(
            profiles: [
                "phil": profile(id: "phil", primary: "philosophy", shares: ["philosophy": 0.85, "research": 0.15]),
                "tech": profile(id: "tech", primary: "technology", shares: ["technology": 0.95]),
                "mixed": profile(id: "mixed", primary: "technology", shares: ["technology": 0.70, "philosophy": 0.30])
            ],
            updatedAt: start
        )
        let library = ThreadLibrary(threads: [philosophy, tech, mixed])
        var filters = GraphFilters.default
        filters.grouping = .region
        filters.topicRoots = ["philosophy"]
        filters.maxThreads = 2

        let graph = GraphBuilder.build(library: library, filters: filters, topicAnalysis: analysis)
        XCTAssertEqual(
            Set(graph.threadNodes.compactMap(\.threadID)),
            ["phil", "mixed"],
            "technology-only threads are scoped out before the cap; the 30% mixed thread qualifies"
        )
        XCTAssertEqual(graph.groupNodes.map(\.id), ["region:philosophy", "region:philosophy/general"])

        filters.topicShareThreshold = 0.5
        let strict = GraphBuilder.build(library: library, filters: filters, topicAnalysis: analysis)
        XCTAssertEqual(strict.threadNodes.compactMap(\.threadID), ["phil"], "weak shares do not qualify")
    }
}

// MARK: - Graph queries

final class MindMapGraphTests: XCTestCase {

    private func library() -> ThreadLibrary {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        var threads: [ConversationThread] = []
        for index in 0..<6 {
            let isEven = index % 2 == 0
            let provider: Provider = isEven ? .chatgpt : .gemini
            let title = isEven ? "SwiftUI canvas notes" : "Japanese kanji practice"
            let text = isEven
                ? "swiftui canvas rendering performance"
                : "kanji vocabulary practice"
            threads.append(ConversationThread(
                id: "t\(index)",
                provider: provider,
                title: title,
                createdAt: start,
                updatedAt: start.addingTimeInterval(TimeInterval(index)),
                messages: [ChatMessage(id: "m\(index)", role: .user, text: text)]
            ))
        }
        return ThreadLibrary(threads: threads)
    }

    func testNodeLookupAndCollections() {
        let graph = GraphBuilder.build(library: library(), filters: .default)
        XCTAssertNil(graph.node(id: nil))
        XCTAssertNil(graph.node(id: "missing"))
        XCTAssertEqual(graph.node(id: "root")?.kind, .root)
        XCTAssertEqual(graph.groupNodes.count, 2)
        XCTAssertEqual(graph.rootGroups.count, graph.groupNodes.count)
        XCTAssertEqual(graph.node(forThread: "t0")?.threadID, "t0")
        XCTAssertNil(graph.node(forThread: "missing"))
        XCTAssertFalse(graph.isEmpty)
        XCTAssertFalse(graph.hasCostData)
    }

    func testAdjacencyIsSymmetric() {
        let graph = GraphBuilder.build(library: library(), filters: .default)
        let adjacent = graph.adjacent
        for (source, targets) in adjacent {
            for target in targets {
                XCTAssertTrue(adjacent[target]?.contains(source) ?? false, "\(source) -> \(target)")
            }
        }
        let adjacency = graph.adjacency
        XCTAssertEqual(Set(adjacency["root"] ?? []), adjacent["root"] ?? [])
        XCTAssertTrue(adjacency.values.allSatisfy { !$0.isEmpty })
    }

    func testFocusPathsForEveryNodeKind() throws {
        let graph = GraphBuilder.build(library: library(), filters: .default)
        XCTAssertTrue(graph.focusPath(for: nil).isEmpty)
        XCTAssertTrue(graph.focusPath(for: "missing").isEmpty)

        XCTAssertEqual(graph.focusPath(for: "root"), Set(graph.nodes.map(\.id)))

        let group = try XCTUnwrap(graph.groupNodes.first)
        let groupPath = graph.focusPath(for: group.id)
        XCTAssertTrue(groupPath.contains(group.id))
        XCTAssertTrue(groupPath.contains("root"))
        XCTAssertTrue(groupPath.contains { $0.hasPrefix("thread:") })
        XCTAssertTrue(groupPath.contains { $0.hasPrefix("tag:") })

        let thread = try XCTUnwrap(graph.threadNodes.first)
        let threadPath = graph.focusPath(for: thread.id)
        XCTAssertTrue(threadPath.contains(thread.id))
        XCTAssertTrue(threadPath.contains(thread.groupID!))
        XCTAssertTrue(threadPath.contains("root"))
        XCTAssertTrue(threadPath.contains { $0.hasPrefix("tag:") })

        let tag = try XCTUnwrap(graph.tagNodes.first)
        let tagPath = graph.focusPath(for: tag.id)
        XCTAssertTrue(tagPath.contains(tag.id))
        XCTAssertTrue(tagPath.contains("root"))
        XCTAssertTrue(tagPath.contains { $0.hasPrefix("thread:") })
        XCTAssertTrue(tagPath.contains { $0.hasPrefix("group:") })
    }

    func testRegionHierarchyQueries() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let threads = [
            ConversationThread(
                id: "tech",
                provider: .chatgpt,
                title: "Database migration for the Swift API",
                createdAt: start,
                messages: [
                    ChatMessage(
                        id: "1",
                        role: .user,
                        text: "The Swift API endpoint fails after the database schema migration. Debug the backend."
                    ),
                    ChatMessage(id: "2", role: .assistant, text: "Check the migration and the logs.")
                ]
            ),
            ConversationThread(
                id: "legal",
                provider: .claude,
                title: "NDA and liability review",
                createdAt: start,
                messages: [
                    ChatMessage(
                        id: "3",
                        role: .user,
                        text: "Please review the contract clause about liability and the NDA. The jurisdiction looks wrong."
                    ),
                    ChatMessage(id: "4", role: .assistant, text: "The indemnity clause needs counsel.")
                ]
            )
        ]
        var filters = GraphFilters.default
        filters.grouping = .region
        let graph = GraphBuilder.build(library: ThreadLibrary(threads: threads), filters: filters)

        let roots = graph.rootGroups
        XCTAssertGreaterThanOrEqual(roots.count, 2)
        for root in roots {
            let descendants = graph.descendantGroupIDs(of: root.id)
            XCTAssertTrue(descendants.contains(root.id))
            let children = graph.childGroups(of: root.id)
            XCTAssertFalse(children.isEmpty)
            for child in children {
                XCTAssertTrue(descendants.contains(child.id))
                XCTAssertTrue(graph.descendantGroupIDs(of: child.id).contains(child.id))
            }
        }
        XCTAssertTrue(graph.descendantGroupIDs(of: "missing").contains("missing"))
    }
}
