import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MindMapCore

// MARK: - Time window

enum TimeWindow: String, CaseIterable, Identifiable {
    case all
    case year
    case ninety
    case thirty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "ALL"
        case .year: return "1Y"
        case .ninety: return "90D"
        case .thirty: return "30D"
        }
    }

    var since: Date? {
        let now = Date()
        switch self {
        case .all: return nil
        case .year: return Calendar.current.date(byAdding: .year, value: -1, to: now)
        case .ninety: return Calendar.current.date(byAdding: .day, value: -90, to: now)
        case .thirty: return Calendar.current.date(byAdding: .day, value: -30, to: now)
        }
    }
}

// MARK: - Toast

struct ToastMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case info
        case success
        case error
    }

    let id = UUID()
    var text: String
    var detail: String?
    var kind: Kind = .info
}

// MARK: - Visualization mode

enum VisualizationMode: String, CaseIterable, Identifiable {
    case map
    case cloud
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .map: return "MAP"
        case .cloud: return "CLOUD"
        case .hybrid: return "HYBRID"
        }
    }

    var title: String {
        switch self {
        case .map: return "Constellation"
        case .cloud: return "Word Cloud"
        case .hybrid: return "Hybrid Cloud"
        }
    }

    var icon: String {
        switch self {
        case .map: return "point.3.connected.trianglepath.dotted"
        case .cloud: return "cloud"
        case .hybrid: return "circle.hexagongrid"
        }
    }

    var showsCloudWords: Bool { self != .map }
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {

    // Library & graph
    @Published private(set) var library: ThreadLibrary = .empty
    @Published private(set) var graph: MindMapGraph = .empty
    @Published private(set) var visibleThreads: [ConversationThread] = []
    @Published private(set) var isImporting = false
    @Published private(set) var lastImportSummary: String?
    @Published private(set) var lastImportDate: Date?

    /// Segment-level topic analysis for the whole library. Built once per
    /// archive change and cached in Application Support as `topics.json`.
    @Published private(set) var topicAnalysis: TopicAnalysis = .empty

    /// Bumped on every graph rebuild. Lets view-layer caches detect a new
    /// graph without hashing the node set on each render.
    private(set) var graphRevision = 0

    // Filters
    @Published var providers: Set<Provider> = Set(Provider.allCases) {
        didSet { rebuild() }
    }
    @Published var grouping: GroupingMode = .provider {
        didSet {
            if grouping == .region { refreshTopicAnalysis() }
            rebuild(refit: true)
        }
    }
    @Published var timeWindow: TimeWindow = .all {
        didSet { rebuild() }
    }
    @Published var showTags: Bool = true {
        didSet { rebuild() }
    }
    @Published var searchText: String = "" {
        didSet { scheduleSearchRebuild() }
    }

    // View toggles
    @Published var showLabels: Bool = true
    /// Draw each hub's real name inside the node instead of the generic
    /// "TOPIC" monogram. On by default; labels remain independently toggleable.
    @Published var showNodeNames: Bool = true
    /// Opt-in spend heat. Off by default; only meaningful for archives that
    /// carry provider-reported cost (OpenCode).
    @Published var showSpend: Bool = false
    @Published var motionEnabled: Bool = true
    @Published var viewMode: VisualizationMode = .map {
        didSet {
            // Both cloud lenses are drawn from shared tag nodes, so tags must
            // be part of the graph while either one is active.
            if viewMode.showsCloudWords, !showTags { showTags = true }
        }
    }
    @Published var is3D: Bool = false {
        didSet { engine.setSpatialMode(is3D) }
    }

    // Selection & chrome
    @Published var selectedNodeID: String?
    @Published var hoveredNodeID: String?
    @Published var toast: ToastMessage?
    @Published var searchFocusRequest = 0
    @Published var showHelp = false
    @Published var showResetConfirmation = false

    let engine = GraphEngine()
    private let store = ThreadStore()
    private let topicStore = TopicStore()
    private var searchTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {
        bootstrap()
    }

    // MARK: - Bootstrap

    private func bootstrap() {
        if store.exists {
            do {
                library = try store.load()
            } catch {
                showToast(
                    "Could not read local library",
                    detail: error.localizedDescription,
                    kind: .error
                )
            }
        } else {
            // First launch: a curated dataset makes the map immediately useful.
            library = DemoData.make()
        }

        topicStore.ensureTaxonomyFile()
        topicAnalysis = (try? topicStore.load()) ?? .empty
        refreshTopicAnalysis()
        rebuild(refit: true)
        if library.hasDemoData {
            lastImportSummary = "DEMO SIGNAL"
        }
    }

    func reloadLibrary() {
        do {
            library = store.exists ? try store.load() : DemoData.make()
            selectedNodeID = nil
            refreshTopicAnalysis()
            rebuild(refit: true)
            showToast(
                "Library reloaded",
                detail: "\(library.threads.count) threads · \(Format.compactCount(library.messageCount)) messages",
                kind: .success
            )
        } catch {
            showToast("Reload failed", detail: error.localizedDescription, kind: .error)
        }
    }

    // MARK: - Rebuild

    private func scheduleSearchRebuild() {
        searchTask?.cancel()
        let text = searchText
        if text.isEmpty {
            rebuild()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            self?.rebuild()
        }
    }

    private var filters: GraphFilters {
        GraphFilters(
            providers: providers,
            searchText: searchText,
            since: timeWindow.since,
            grouping: grouping,
            includeTags: showTags,
            maxThreads: 420
        )
    }

    private func rebuild(refit: Bool = false) {
        let filters = self.filters
        graph = GraphBuilder.build(
            library: library,
            filters: filters,
            topicAnalysis: topicAnalysis
        )
        graphRevision &+= 1
        visibleThreads = library.threads
            .filter { filters.matches($0) }
            .sorted { $0.updatedAt > $1.updatedAt }

        if let selectedNodeID, graph.node(id: selectedNodeID) == nil {
            self.selectedNodeID = nil
        }
        if let hoveredNodeID, graph.node(id: hoveredNodeID) == nil {
            self.hoveredNodeID = nil
        }
        engine.setGraph(graph, refit: refit)
    }

    // MARK: - Selection

    func select(_ nodeID: String?, focus: Bool = false) {
        selectedNodeID = nodeID
        guard let nodeID, let node = graph.node(id: nodeID) else { return }
        guard focus else { return }
        // Center the surrounding constellation rather than the outer-edge node,
        // so the inspector never opens onto an empty corner of the map.
        if node.kind == .thread, let groupID = node.groupID {
            engine.focus(nodeID: groupID, zoom: min(max(engine.frame.camera.zoom, 0.62), 0.92))
        } else {
            engine.focus(nodeID: nodeID, zoom: min(max(engine.frame.camera.zoom, 0.62), 0.95))
        }
    }

    func select(threadID: String, focus: Bool = true) {
        guard let node = graph.node(forThread: threadID) else { return }
        select(node.id, focus: focus)
    }

    func deselect() {
        selectedNodeID = nil
    }

    func threads(for node: MindMapNode) -> [ConversationThread] {
        let ids: Set<String>
        switch node.kind {
        case .thread:
            ids = node.threadID.map { [$0] } ?? []
        case .group:
            let groupIDs = graph.descendantGroupIDs(of: node.id)
            ids = Set(graph.threadNodes.filter { node in
                guard let groupID = node.groupID else { return false }
                return groupIDs.contains(groupID)
            }.compactMap(\.threadID))
        case .tag:
            let threadNodeIDs = Set(graph.adjacency[node.id] ?? [])
            ids = Set(graph.threadNodes.filter { threadNodeIDs.contains($0.id) }.compactMap(\.threadID))
        case .root:
            ids = Set(graph.threadNodes.compactMap(\.threadID))
        }
        let byID = Dictionary(uniqueKeysWithValues: library.threads.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func thread(for node: MindMapNode) -> ConversationThread? {
        guard let threadID = node.threadID else { return nil }
        return library.threads.first { $0.id == threadID }
    }

    var selectedNode: MindMapNode? {
        graph.node(id: selectedNodeID)
    }

    // MARK: - Filters

    func toggleProvider(_ provider: Provider) {
        if providers.contains(provider) {
            providers.remove(provider)
        } else {
            providers.insert(provider)
        }
    }

    func setAllProviders(_ enabled: Bool) {
        providers = enabled ? Set(Provider.allCases) : []
    }

    func providerCount(_ provider: Provider) -> Int {
        library.threads.filter { $0.provider == provider }.count
    }

    func clearSearch() {
        searchText = ""
    }

    func focusSearch() {
        searchFocusRequest += 1
    }

    func resetFilters() {
        providers = Set(Provider.allCases)
        grouping = .provider
        timeWindow = .all
        searchText = ""
        showTags = true
        selectedNodeID = nil
    }

    func toggle3D() {
        is3D.toggle()
    }

    // MARK: - Import

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import conversation exports"
        panel.message = "Choose ChatGPT / Gemini / Claude exports, a Takeout folder, MINDME JSON, or an OpenCode database."
        panel.prompt = "Import"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        var types: [UTType] = [.json, .html, .plainText]
        for ext in ["db", "sqlite", "sqlite3"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    /// Reads OpenCode's local SQLite library in place. Nothing is copied or
    /// uploaded; only prompts and assistant text are normalized.
    func importOpenCodeSessions() {
        guard !isImporting else { return }
        guard let database = OpenCodeImporter.defaultDatabaseURL() else {
            showToast(
                "No OpenCode library found",
                detail: "Expected ~/.local/share/opencode/opencode.db. If your sessions live elsewhere, drag the .db file onto the window.",
                kind: .error
            )
            return
        }
        importFiles([database])
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        searchTask?.cancel()

        Task { [weak self] in
            let result: Result<ImportResult, Error>
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    try ConversationImporter.importFiles(at: urls)
                }.value
                result = .success(imported)
            } catch {
                result = .failure(error)
            }

            guard let self else { return }
            self.isImporting = false
            switch result {
            case .success(let imported):
                self.applyImport(imported)
            case .failure(let error):
                self.showToast("Import failed", detail: error.localizedDescription, kind: .error)
            }
        }
    }

    private func applyImport(_ result: ImportResult) {
        let demoRemoved = library.hasDemoData
        if demoRemoved { library.removeDemoData() }

        let counts = library.merge(result.threads)
        library.lastImport = Date()
        lastImportDate = Date()
        lastImportSummary = "\(counts.added) NEW · \(counts.updated) UPDATED"
        selectedNodeID = nil
        refreshTopicAnalysis()
        rebuild(refit: true)

        do {
            try store.save(library)
        } catch {
            showToast("Imported, but could not save", detail: error.localizedDescription, kind: .error)
            return
        }

        var detail = "\(counts.added) added · \(counts.updated) updated"
        if demoRemoved { detail += " · demo data cleared" }
        if !result.warnings.isEmpty {
            detail += " · \(result.warnings.count) skipped"
        }
        showToast(
            "Imported \(result.threads.count) threads",
            detail: detail,
            kind: .success
        )
    }

    func clearDemoData() {
        guard library.hasDemoData else { return }
        library.removeDemoData()
        selectedNodeID = nil
        lastImportSummary = nil
        lastImportDate = nil
        refreshTopicAnalysis()
        rebuild(refit: true)
        do {
            try store.save(library)
            showToast("Demo data cleared", detail: "The map is empty until you import an export.", kind: .info)
        } catch {
            showToast("Could not save library", detail: error.localizedDescription, kind: .error)
        }
    }

    func loadDemoData() {
        library.merge(DemoData.make().threads)
        library.lastImport = Date()
        selectedNodeID = nil
        refreshTopicAnalysis()
        rebuild(refit: true)
        try? store.save(library)
        lastImportSummary = "DEMO SIGNAL"
        lastImportDate = Date()
        showToast("Demo dataset loaded", detail: "\(library.threads.count) synthetic conversations", kind: .success)
    }

    func resetEverything() {
        do {
            try store.deleteLibrary()
            try store.save(.empty)
            try? topicStore.delete()
        } catch {
            showToast("Reset failed", detail: error.localizedDescription, kind: .error)
            return
        }
        library = .empty
        topicAnalysis = .empty
        selectedNodeID = nil
        lastImportSummary = nil
        lastImportDate = nil
        rebuild(refit: true)
        showToast("Local library cleared", detail: "Nothing was sent anywhere.", kind: .info)
    }

    func revealLibrary() {
        store.revealInFinder()
    }

    // MARK: - Toast

    func showToast(_ text: String, detail: String? = nil, kind: ToastMessage.Kind = .info) {
        toastTask?.cancel()
        let message = ToastMessage(text: text, detail: detail, kind: kind)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            toast = message
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self?.toast = nil
            }
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = nil }
    }

    // MARK: - Topics

    /// Rebuilds segment profiles when the archive changes. Profiles are cached
    /// per thread content hash, so adding one conversation does not reclassify
    /// the rest. Called synchronously on lifecycle events; the segmenter and
    /// hashing embedder keep this in the low milliseconds per thread.
    private func refreshTopicAnalysis(force: Bool = false) {
        guard !library.threads.isEmpty else {
            topicAnalysis = .empty
            try? topicStore.save(.empty)
            return
        }
        let cached = force ? nil : topicAnalysis
        // Reloaded each time so edits to taxonomy.json are picked up by the
        // Reclassify Topics command without a relaunch.
        let taxonomy = topicStore.loadTaxonomy() ?? .default
        let analysis = TopicPipeline(taxonomy: taxonomy).analyze(library, cached: cached)
        guard force
                || analysis.libraryHash != topicAnalysis.libraryHash
                || analysis.profiles.count != topicAnalysis.profiles.count
                || analysis.version != topicAnalysis.version
                || analysis.taxonomy != topicAnalysis.taxonomy
                || analysis.embedderID != topicAnalysis.embedderID else {
            return
        }
        topicAnalysis = analysis
        try? topicStore.save(analysis)
    }

    func reclassifyTopics() {
        refreshTopicAnalysis(force: true)
        rebuild(refit: true)
        let segmentCount = topicAnalysis.profiles.values.reduce(0) { $0 + $1.segments.count }
        showToast(
            "Topics reclassified",
            detail: "\(topicAnalysis.profiles.count) threads · \(segmentCount) regions",
            kind: .success
        )
    }

    func topicProfile(for threadID: String) -> ThreadTopicProfile? {
        topicAnalysis.profiles[threadID]
    }

    func topicLabel(for topicID: String) -> String {
        topicAnalysis.taxonomy.label(for: topicID)
    }

    // MARK: - Spend

    var hasSpendData: Bool {
        library.threads.contains(where: \.hasCostData)
    }

    func toggleSpend() {
        if !showSpend, !hasSpendData {
            showToast(
                "No spend data in this library",
                detail: "Import OpenCode sessions to see cost heat across regions.",
                kind: .info
            )
            return
        }
        showSpend.toggle()
    }

    // MARK: - Derived

    var hasThreads: Bool { !library.threads.isEmpty }

    var selectedThreadTags: [String] {
        guard let selectedNode else { return [] }
        if selectedNode.kind == .tag { return [selectedNode.label] }
        let threadIDs: Set<String>
        if selectedNode.kind == .thread {
            threadIDs = selectedNode.threadID.map { [$0] } ?? []
        } else {
            threadIDs = Set(threads(for: selectedNode).map(\.id))
        }
        var seen = Set<String>()
        var tags: [String] = []
        for threadID in threadIDs {
            for keyword in graph.keywordsByThread[threadID] ?? [] {
                if seen.insert(keyword.term).inserted { tags.append(keyword.term) }
            }
        }
        return Array(tags.prefix(10))
    }
}
