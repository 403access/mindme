import XCTest
import Foundation
import MindMapCore

@MainActor
final class AppModelTests: XCTestCase {

    private func thread(
        id: String,
        title: String,
        text: String,
        provider: Provider = .chatgpt,
        updatedAt: Date = Date()
    ) -> ConversationThread {
        ConversationThread(
            id: id,
            provider: provider,
            title: title,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            messages: [ChatMessage(id: "\(id)-m", role: .user, text: text, timestamp: updatedAt)]
        )
    }

    private func makeModel(threads: [ConversationThread]?) throws -> (AppModel, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapAppModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ThreadStore(directory: directory)
        if let threads {
            try store.save(ThreadLibrary(threads: threads, lastImport: Date()))
        }
        let model = AppModel(store: store, topicStore: TopicStore(directory: directory))
        return (model, directory)
    }

    private func threeThreads(updatedAt: Date = Date()) -> [ConversationThread] {
        [
            thread(
                id: "t1",
                title: "SwiftUI canvas performance",
                text: "swiftui canvas rendering performance tuning",
                updatedAt: updatedAt
            ),
            thread(
                id: "t2",
                title: "SwiftUI canvas rendering",
                text: "swiftui canvas rendering pipeline details",
                provider: .gemini,
                updatedAt: updatedAt
            ),
            thread(
                id: "t3",
                title: "Japanese kanji practice",
                text: "kanji vocabulary practice for beginners",
                provider: .claude,
                updatedAt: updatedAt
            )
        ]
    }

    func testBootstrapLoadsExistingLibrary() throws {
        let (model, directory) = try makeModel(threads: threeThreads())
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(model.library.threads.count, 3)
        XCTAssertFalse(model.library.hasDemoData)
        XCTAssertNil(model.lastImportSummary)
        XCTAssertEqual(model.graph.stats.threadCount, 3)
        XCTAssertEqual(model.topicAnalysis.profiles.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("taxonomy.json").path))
        XCTAssertTrue(model.hasThreads)
        XCTAssertEqual(model.providers, Set(Provider.allCases))
        XCTAssertEqual(model.grouping, .provider)
        XCTAssertEqual(model.timeWindow, .all)
        XCTAssertTrue(model.showTags)
        XCTAssertTrue(model.showLabels)
        XCTAssertTrue(model.showNodeNames)
        XCTAssertFalse(model.showSpend)
        XCTAssertTrue(model.motionEnabled)
        XCTAssertEqual(model.viewMode, .map)
    }

    func testBootstrapSeedsDemoOnFirstLaunch() throws {
        let (model, directory) = try makeModel(threads: nil)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(model.library.hasDemoData)
        XCTAssertEqual(model.lastImportSummary, "DEMO SIGNAL")
        XCTAssertEqual(model.graph.stats.threadCount, model.library.threads.count)
        XCTAssertFalse(model.topicAnalysis.isEmpty)
        XCTAssertEqual(model.topicAnalysis.profiles.count, model.library.threads.count)
    }

    func testProviderFiltersAndCounts() throws {
        let (model, directory) = try makeModel(threads: threeThreads())
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(model.providerCount(.chatgpt), 1)
        XCTAssertEqual(model.providerCount(.gemini), 1)
        XCTAssertEqual(model.providerCount(.claude), 1)
        XCTAssertEqual(model.providerCount(.opencode), 0)

        model.toggleProvider(.gemini)
        XCTAssertEqual(model.graph.stats.threadCount, 2)
        model.toggleProvider(.gemini)
        XCTAssertEqual(model.graph.stats.threadCount, 3)

        model.setAllProviders(false)
        XCTAssertTrue(model.providers.isEmpty)
        XCTAssertTrue(model.graph.isEmpty)
        XCTAssertTrue(model.hasThreads, "filters never delete the library")

        model.setAllProviders(true)
        XCTAssertEqual(model.providers, Set(Provider.allCases))
        XCTAssertEqual(model.graph.stats.threadCount, 3)
    }

    func testGroupingAndTagTogglesRebuildTheGraph() throws {
        let (model, directory) = try makeModel(threads: threeThreads())
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(model.graph.tagNodes.isEmpty)
        model.showTags = false
        XCTAssertTrue(model.graph.tagNodes.isEmpty)
        model.showTags = true
        XCTAssertFalse(model.graph.tagNodes.isEmpty)

        model.grouping = .region
        XCTAssertFalse(model.topicAnalysis.isEmpty)
        XCTAssertTrue(model.graph.groupNodes.contains { $0.parentID != nil })
        XCTAssertTrue(model.graph.edges.contains { $0.kind == .regionGroup })

        model.grouping = .topic
        XCTAssertFalse(model.graph.groupNodes.isEmpty)
    }

    func testTimeWindowFiltersTheGraph() throws {
        let old = Date().addingTimeInterval(-200 * 86_400)
        let (model, directory) = try makeModel(threads: threeThreads(updatedAt: old))
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(model.graph.stats.threadCount, 3)
        model.timeWindow = .thirty
        XCTAssertTrue(model.graph.isEmpty)
        model.timeWindow = .ninety
        XCTAssertTrue(model.graph.isEmpty)
        model.timeWindow = .year
        XCTAssertEqual(model.graph.stats.threadCount, 3)
        model.timeWindow = .all
        XCTAssertEqual(model.graph.stats.threadCount, 3)
    }

    func testSearchHighlightsInPlaceThenIsolates() async throws {
        let (model, directory) = try makeModel(threads: threeThreads())
        defer { try? FileManager.default.removeItem(at: directory) }

        model.searchText = "kanji"
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(model.visibleThreads.map(\.id), ["t3"])
        XCTAssertEqual(model.searchMatchNodeIDs.count, 1)
        XCTAssertTrue(model.isSearchHighlightActive)
        XCTAssertEqual(model.graph.stats.threadCount, 3, "highlight mode keeps the full map")

        model.applySearchIsolation()
        XCTAssertTrue(model.searchIsolation)
        XCTAssertEqual(model.graph.stats.threadCount, 1)
        XCTAssertFalse(model.isSearchHighlightActive)
        XCTAssertEqual(model.visibleThreads.map(\.id), ["t3"])

        model.toggleSearchIsolation()
        XCTAssertFalse(model.searchIsolation)
        XCTAssertEqual(model.graph.stats.threadCount, 3)
        XCTAssertTrue(model.isSearchHighlightActive)

        model.clearSearch()
        XCTAssertEqual(model.searchText, "")
        XCTAssertFalse(model.searchIsolation)
        XCTAssertTrue(model.searchMatchNodeIDs.isEmpty)
        XCTAssertEqual(model.visibleThreads.count, 3)
    }

    func testSearchIsolationRequiresAQuery() throws {
        let (model, directory) = try makeModel(threads: threeThreads())
        defer { try? FileManager.default.removeItem(at: directory) }

        model.applySearchIsolation()
        XCTAssertFalse(model.searchIsolation)
        model.toggleSearchIsolation()
        XCTAssertFalse(model.searchIsolation)

        model.searchText = "swiftui"
        model.applySearchIsolation()
        XCTAssertTrue(model.searchIsolation)
        model.applySearchIsolation()
        XCTAssertTrue(model.searchIsolation, "applying twice is harmless")
    }

    func testSelectionResolvesThreadsAndTags() throws {
        let (model, directory) = try makeModel(threads: threeThreads())
        defer { try? FileManager.default.removeItem(at: directory) }

        model.select(threadID: "t1")
        let threadNode = try XCTUnwrap(model.selectedNode)
        XCTAssertEqual(threadNode.kind, .thread)
        XCTAssertEqual(model.threads(for: threadNode).map(\.id), ["t1"])
        XCTAssertEqual(model.thread(for: threadNode)?.id, "t1")
        XCTAssertFalse(model.selectedThreadTags.isEmpty)

        let group = try XCTUnwrap(model.graph.groupNodes.first { $0.provider == .chatgpt })
        model.select(group.id)
        XCTAssertEqual(model.threads(for: group).map(\.id), ["t1"])
        XCTAssertEqual(model.thread(for: group), nil)

        let tag = try XCTUnwrap(model.graph.tagNodes.first)
        model.select(tag.id)
        XCTAssertEqual(model.threads(for: tag).count, 2)
        XCTAssertEqual(model.selectedThreadTags, [tag.label])

        let root = try XCTUnwrap(model.graph.rootNode)
        model.select(root.id)
        XCTAssertEqual(model.threads(for: root).count, 3)
        XCTAssertFalse(model.selectedThreadTags.isEmpty)

        model.deselect()
        XCTAssertNil(model.selectedNodeID)
        model.select(threadID: "missing")
        XCTAssertNil(model.selectedNodeID)
    }

    func testImportMergesClearsDemoAndPersists() async throws {
        let (model, directory) = try makeModel(threads: nil)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(model.library.hasDemoData)

        let url = directory.appendingPathComponent("import.json")
        try Data("""
        {"threads": [{"id": "imported", "provider": "other", "title": "Imported thread",
          "messages": [{"role": "user", "text": "hello from an import"}]}]}
        """.utf8).write(to: url)

        model.importFiles([url])
        for _ in 0..<200 {
            if !model.isImporting { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.library.threads.map(\.id), ["other:imported"])
        XCTAssertFalse(model.library.hasDemoData)
        XCTAssertEqual(model.lastImportSummary, "1 NEW · 0 UPDATED")
        XCTAssertNotNil(model.lastImportDate)
        XCTAssertEqual(model.graph.stats.threadCount, 1)
        XCTAssertEqual(model.toast?.kind, .success)
        XCTAssertEqual(model.toast?.text, "Imported 1 threads")
        XCTAssertTrue(model.toast?.detail?.contains("demo data cleared") == true)

        let stored = try ThreadStore(directory: directory).load()
        XCTAssertEqual(stored.threads.count, 1)
        XCTAssertEqual(stored.threads.first?.id, "other:imported")
    }

    func testImportFailureShowsAnErrorToast() async throws {
        let (model, directory) = try makeModel(threads: threeThreads())
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("broken.json")
        try Data("{not json".utf8).write(to: url)

        model.importFiles([url])
        for _ in 0..<100 {
            if !model.isImporting { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.toast?.kind, .error)
        XCTAssertEqual(model.toast?.text, "Import failed")
        XCTAssertEqual(model.library.threads.count, 3, "a failed import leaves the library alone")
    }

    func testReloadLibraryPicksUpExternalChanges() throws {
        let (model, directory) = try makeModel(threads: [threeThreads()[0]])
        defer { try? FileManager.default.removeItem(at: directory) }

        try ThreadStore(directory: directory).save(ThreadLibrary(threads: threeThreads()))
        model.reloadLibrary()
        XCTAssertEqual(model.library.threads.count, 3)
        XCTAssertEqual(model.graph.stats.threadCount, 3)
        XCTAssertEqual(model.toast?.text, "Library reloaded")
        XCTAssertEqual(model.toast?.kind, .success)
        XCTAssertNil(model.selectedNodeID)
    }

    func testLoadClearAndResetLibraryLifecycle() throws {
        let real = thread(id: "real", title: "Real", text: "a real conversation")
        let (model, directory) = try makeModel(threads: [real])
        defer { try? FileManager.default.removeItem(at: directory) }

        model.loadDemoData()
        XCTAssertGreaterThan(model.library.threads.count, 1)
        XCTAssertTrue(model.library.hasDemoData)
        XCTAssertEqual(model.lastImportSummary, "DEMO SIGNAL")
        XCTAssertEqual(model.toast?.text, "Demo dataset loaded")

        model.clearDemoData()
        XCTAssertEqual(model.library.threads.map(\.id), ["real"])
        XCTAssertFalse(model.library.hasDemoData)
        XCTAssertNil(model.lastImportSummary)
        XCTAssertEqual(try ThreadStore(directory: directory).load().threads.count, 1)

        model.resetEverything()
        XCTAssertTrue(model.library.threads.isEmpty)
        XCTAssertTrue(model.topicAnalysis.isEmpty)
        XCTAssertNil(model.selectedNodeID)
        XCTAssertNil(model.lastImportSummary)
        XCTAssertEqual(model.toast?.text, "Local library cleared")
        XCTAssertTrue(try ThreadStore(directory: directory).load().threads.isEmpty)
    }

    func testSpendToggleOnlyWorksWithCostData() throws {
        let (plain, plainDirectory) = try makeModel(threads: threeThreads())
        defer { try? FileManager.default.removeItem(at: plainDirectory) }
        XCTAssertFalse(plain.hasSpendData)
        plain.toggleSpend()
        XCTAssertFalse(plain.showSpend)
        XCTAssertEqual(plain.toast?.text, "No spend data in this library")

        let costly = thread(id: "cost", title: "Costly", text: "spend", provider: .opencode)
        var costlyThread = costly
        costlyThread.cost = 1.25
        let (model, directory) = try makeModel(threads: [costlyThread])
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(model.hasSpendData)
        model.toggleSpend()
        XCTAssertTrue(model.showSpend)
        model.toggleSpend()
        XCTAssertFalse(model.showSpend)
    }

    func testTopicLookupAndReclassify() throws {
        let tech = thread(
            id: "tech",
            title: "Database migration for the Swift API",
            text: "The Swift API endpoint fails after the database schema migration. Debug the backend and compile a fix."
        )
        let (model, directory) = try makeModel(threads: [tech])
        defer { try? FileManager.default.removeItem(at: directory) }

        let profile = try XCTUnwrap(model.topicProfile(for: "tech"))
        XCTAssertEqual(profile.primaryRegionID, "technology")
        XCTAssertNil(model.topicProfile(for: "missing"))
        XCTAssertEqual(model.topicLabel(for: "technology"), "Technology")
        XCTAssertEqual(model.topicLabel(for: "unknown/topic"), "unknown/topic")

        model.reclassifyTopics()
        XCTAssertEqual(model.toast?.text, "Topics reclassified")
        XCTAssertEqual(model.toast?.kind, .success)
        XCTAssertEqual(model.topicAnalysis.profiles.count, 1)
    }

    func testSearchFocusAndResetFilters() throws {
        let (model, directory) = try makeModel(threads: threeThreads())
        defer { try? FileManager.default.removeItem(at: directory) }

        let focusRequests = model.searchFocusRequest
        model.focusSearch()
        XCTAssertEqual(model.searchFocusRequest, focusRequests + 1)

        model.searchText = "swiftui"
        model.providers = [.gemini]
        model.grouping = .region
        model.timeWindow = .thirty
        model.showTags = false
        model.selectedNodeID = "root"

        model.resetFilters()
        XCTAssertEqual(model.providers, Set(Provider.allCases))
        XCTAssertEqual(model.grouping, .provider)
        XCTAssertEqual(model.timeWindow, .all)
        XCTAssertEqual(model.searchText, "")
        XCTAssertFalse(model.searchIsolation)
        XCTAssertTrue(model.showTags)
        XCTAssertNil(model.selectedNodeID)
    }
}
