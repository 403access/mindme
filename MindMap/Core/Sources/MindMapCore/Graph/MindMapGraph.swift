import Foundation

// MARK: - Grouping

public enum GroupingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case provider
    case topic
    case era

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .provider: return "PROVIDER"
        case .topic: return "TOPIC"
        case .era: return "ERA"
        }
    }
}

// MARK: - Filters

public struct GraphFilters: Equatable, Sendable {
    public var providers: Set<Provider>
    public var searchText: String
    public var since: Date?
    public var grouping: GroupingMode
    public var includeTags: Bool
    public var maxThreads: Int

    public init(
        providers: Set<Provider> = Set(Provider.allCases),
        searchText: String = "",
        since: Date? = nil,
        grouping: GroupingMode = .provider,
        includeTags: Bool = true,
        maxThreads: Int = 420
    ) {
        self.providers = providers
        self.searchText = searchText
        self.since = since
        self.grouping = grouping
        self.includeTags = includeTags
        self.maxThreads = maxThreads
    }

    public static let `default` = GraphFilters()

    public func matches(_ thread: ConversationThread) -> Bool {
        guard providers.contains(thread.provider) else { return false }
        if let since, thread.updatedAt < since { return false }
        let query = TextTools.collapsed(searchText).lowercased()
        guard !query.isEmpty else { return true }
        if thread.title.lowercased().contains(query) { return true }
        if thread.messages.contains(where: { $0.text.lowercased().contains(query) }) { return true }
        // Fall back to an AND search of all query tokens.
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count > 1 else { return false }
        let haystack = (thread.title + " " + thread.messages.map(\.text).joined(separator: " ")).lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

// MARK: - Nodes

public enum NodeKind: String, Codable, Hashable, Sendable {
    case root
    case group
    case thread
    case tag

    public var isHub: Bool { self == .root || self == .group }
}

public struct MindMapNode: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: NodeKind
    public var label: String
    public var subtitle: String?
    public var provider: Provider?
    public var groupID: String?
    public var threadID: String?
    public var tag: String?
    public var weight: Double
    public var colorSeed: Int

    public init(
        id: String,
        kind: NodeKind,
        label: String,
        subtitle: String? = nil,
        provider: Provider? = nil,
        groupID: String? = nil,
        threadID: String? = nil,
        tag: String? = nil,
        weight: Double = 1,
        colorSeed: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.subtitle = subtitle
        self.provider = provider
        self.groupID = groupID
        self.threadID = threadID
        self.tag = tag
        self.weight = weight
        self.colorSeed = colorSeed
    }
}

public enum EdgeKind: String, Codable, Hashable, Sendable {
    case rootGroup
    case groupThread
    case threadTag
}

public struct MindMapEdge: Identifiable, Hashable, Sendable {
    public var id: String
    public var source: String
    public var target: String
    public var kind: EdgeKind
    public var weight: Double

    public init(source: String, target: String, kind: EdgeKind, weight: Double = 1) {
        self.id = "\(source)->\(target)"
        self.source = source
        self.target = target
        self.kind = kind
        self.weight = weight
    }
}

public struct GraphStats: Equatable, Sendable {
    public var threadCount: Int
    public var messageCount: Int
    public var tagCount: Int
    public var groupCount: Int
    public var characterCount: Int
    public var earliest: Date?
    public var latest: Date?
    public var unfilteredThreadCount: Int

    public init(
        threadCount: Int = 0,
        messageCount: Int = 0,
        tagCount: Int = 0,
        groupCount: Int = 0,
        characterCount: Int = 0,
        earliest: Date? = nil,
        latest: Date? = nil,
        unfilteredThreadCount: Int = 0
    ) {
        self.threadCount = threadCount
        self.messageCount = messageCount
        self.tagCount = tagCount
        self.groupCount = groupCount
        self.characterCount = characterCount
        self.earliest = earliest
        self.latest = latest
        self.unfilteredThreadCount = unfilteredThreadCount
    }
}

public struct MindMapGraph: Sendable {
    public var nodes: [MindMapNode]
    public var edges: [MindMapEdge]
    public var stats: GraphStats
    public var filters: GraphFilters
    public var keywordsByThread: [String: [Keyword]]

    public init(
        nodes: [MindMapNode] = [],
        edges: [MindMapEdge] = [],
        stats: GraphStats = GraphStats(),
        filters: GraphFilters = .default,
        keywordsByThread: [String: [Keyword]] = [:]
    ) {
        self.nodes = nodes
        self.edges = edges
        self.stats = stats
        self.filters = filters
        self.keywordsByThread = keywordsByThread
    }

    public static let empty = MindMapGraph()

    public var isEmpty: Bool { stats.threadCount == 0 }

    public func node(id: String?) -> MindMapNode? {
        guard let id else { return nil }
        return nodes.first { $0.id == id }
    }

    public var rootNode: MindMapNode? { nodes.first { $0.kind == .root } }
    public var groupNodes: [MindMapNode] { nodes.filter { $0.kind == .group } }
    public var threadNodes: [MindMapNode] { nodes.filter { $0.kind == .thread } }
    public var tagNodes: [MindMapNode] { nodes.filter { $0.kind == .tag } }

    public func node(forThread threadID: String) -> MindMapNode? {
        nodes.first { $0.threadID == threadID }
    }

    public var adjacent: [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for edge in edges {
            result[edge.source, default: []].insert(edge.target)
            result[edge.target, default: []].insert(edge.source)
        }
        return result
    }

    public var adjacency: [String: [String]] {
        var result: [String: [String]] = [:]
        for edge in edges {
            result[edge.source, default: []].append(edge.target)
            result[edge.target, default: []].append(edge.source)
        }
        return result
    }

    /// The highlighted "signal path" for a focused node.
    public func focusPath(for nodeID: String?) -> Set<String> {
        guard let nodeID, let node = node(id: nodeID) else { return [] }
        switch node.kind {
        case .root:
            return Set(nodes.map(\.id))
        case .group:
            var set: Set<String> = [node.id]
            for edge in edges where edge.source == node.id || edge.target == node.id {
                let other = edge.source == node.id ? edge.target : edge.source
                set.insert(other)
                if edge.kind == .groupThread {
                    for tagEdge in edges where tagEdge.source == other || tagEdge.target == other {
                        set.insert(tagEdge.source == other ? tagEdge.target : tagEdge.source)
                    }
                }
            }
            if let root = rootNode { set.insert(root.id) }
            return set
        case .thread:
            var set: Set<String> = [node.id]
            for edge in edges where edge.source == node.id || edge.target == node.id {
                let other = edge.source == node.id ? edge.target : edge.source
                set.insert(other)
            }
            if let group = node.groupID { set.insert(group) }
            if let root = rootNode { set.insert(root.id) }
            return set
        case .tag:
            var set: Set<String> = [node.id]
            for edge in edges where edge.source == node.id || edge.target == node.id {
                let other = edge.source == node.id ? edge.target : edge.source
                set.insert(other)
                if let group = self.node(id: other)?.groupID { set.insert(group) }
            }
            if let root = rootNode { set.insert(root.id) }
            return set
        }
    }
}
