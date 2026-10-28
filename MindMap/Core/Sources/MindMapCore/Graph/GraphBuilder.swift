import Foundation

/// Turns a filtered thread library into a renderable constellation:
/// root → group hubs → conversations → shared keyword tags.
public enum GraphBuilder {

    public static func build(
        library: ThreadLibrary,
        filters: GraphFilters,
        topicAnalysis: TopicAnalysis? = nil,
        now: Date = Date()
    ) -> MindMapGraph {
        let providerFiltered = library.threads.filter { filters.matches($0) }
        let limited = Array(
            providerFiltered
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(max(0, filters.maxThreads))
        )

        guard !limited.isEmpty else {
            return MindMapGraph(
                nodes: [rootNode(count: 0, groups: 0)],
                edges: [],
                stats: GraphStats(
                    unfilteredThreadCount: library.threads.count
                ),
                filters: filters
            )
        }

        let index = KeywordExtractor.buildIndex(threads: limited, limitPerThread: 7)

        // Group definitions -------------------------------------------------
        var groups: [GroupSpec] = []
        var groupIDByThread: [String: String] = [:]

        switch filters.grouping {
        case .provider:
            let byProvider = Dictionary(grouping: limited, by: \.provider)
            for provider in Provider.allCases {
                guard let threads = byProvider[provider], !threads.isEmpty else { continue }
                let spec = GroupSpec(
                    id: "group:provider:\(provider.rawValue)",
                    label: provider.displayName.uppercased(),
                    subtitle: TextTools.count(threads.count, singular: "THREAD", plural: "THREADS"),
                    provider: provider,
                    colorSeed: provider.order,
                    priority: provider.order,
                    parentID: nil,
                    threadIDs: threads.map(\.id)
                )
                groups.append(spec)
                for thread in threads { groupIDByThread[thread.id] = spec.id }
            }

        case .topic:
            let clusters = TopicClusterer.clusters(
                threads: limited,
                index: index,
                maxTopics: min(14, max(6, 6 + limited.count / 24))
            )
            for (offset, cluster) in clusters.enumerated() {
                let spec = GroupSpec(
                    id: cluster.id,
                    label: KeywordExtractor.prettyLabel(cluster.label).uppercased(),
                    subtitle: TextTools.count(cluster.threadIDs.count, singular: "THREAD", plural: "THREADS"),
                    provider: nil,
                    colorSeed: offset,
                    priority: offset,
                    parentID: nil,
                    threadIDs: cluster.threadIDs
                )
                groups.append(spec)
                for threadID in cluster.threadIDs { groupIDByThread[threadID] = spec.id }
            }
            let assigned = Set(groupIDByThread.keys)
            let leftovers = limited.filter { !assigned.contains($0.id) }
            if !leftovers.isEmpty {
                let spec = GroupSpec(
                    id: "group:topic:misc",
                    label: "MISCELLANY",
                    subtitle: TextTools.count(leftovers.count, singular: "THREAD", plural: "THREADS"),
                    provider: nil,
                    colorSeed: 9,
                    priority: 99,
                    parentID: nil,
                    threadIDs: leftovers.map(\.id)
                )
                groups.append(spec)
                for thread in leftovers { groupIDByThread[thread.id] = spec.id }
            }

        case .region:
            let analysis = regionAnalysis(for: limited, provided: topicAnalysis)
            let roots = analysis.taxonomy.roots
            var threadsByRoot: [String: [String]] = [:]
            var threadsByLeaf: [String: [String]] = [:]
            var costByRoot: [String: Double] = [:]
            var costByLeaf: [String: Double] = [:]

            for thread in limited {
                let profile = analysis.profiles[thread.id]
                // Spend-aware placement: when a conversation's parts have
                // different costs, park it where most of the money went.
                // Without costs this is the usual mass-primary topic.
                let costliest = profile?.topics
                    .filter { $0.cost > 0 }
                    .max { a, b in
                        if abs(a.cost - b.cost) > 0.000001 { return a.cost < b.cost }
                        return a.share < b.share
                    }
                let leafID = costliest?.topicID
                    ?? profile?.primaryTopicID
                    ?? "emerging/misc"
                let rootID = analysis.taxonomy.node(id: leafID)?.parentID
                    ?? profile?.primaryRegionID
                    ?? "emerging"
                threadsByLeaf[leafID, default: []].append(thread.id)
                threadsByRoot[rootID, default: []].append(thread.id)

                let threadCost = profile?.totalCost ?? thread.totalCost
                if threadCost > 0 {
                    costByLeaf[leafID, default: 0] += threadCost
                    costByRoot[rootID, default: 0] += threadCost
                }
            }

            for (rootIndex, root) in roots.enumerated() {
                guard let rootThreads = threadsByRoot[root.id], !rootThreads.isEmpty else { continue }
                let children = analysis.taxonomy.children(of: root.id)
                    .filter { !(threadsByLeaf[$0.id] ?? []).isEmpty }
                let regionID = "region:\(root.id)"
                groups.append(GroupSpec(
                    id: regionID,
                    label: root.label.uppercased(),
                    subtitle: "\(TextTools.count(rootThreads.count, singular: "THREAD", plural: "THREADS")) · \(TextTools.count(children.count, singular: "REGION", plural: "REGIONS"))",
                    provider: nil,
                    colorSeed: rootIndex,
                    priority: rootIndex,
                    parentID: nil,
                    threadIDs: [],
                    displayWeight: Double(rootThreads.count),
                    cost: costByRoot[root.id] ?? 0
                ))

                // A domain with threads but no classified child still needs a
                // visible sub-region; the fallback leaf handles this normally.
                let visibleChildren: [(id: String, label: String, threadIDs: [String])]
                if children.isEmpty {
                    visibleChildren = [("\(root.id)/general", "General", rootThreads)]
                } else {
                    visibleChildren = children.map { child in
                        (child.id, child.label, threadsByLeaf[child.id] ?? [])
                    }
                }

                for child in visibleChildren {
                    let childID = "region:\(child.id)"
                    groups.append(GroupSpec(
                        id: childID,
                        label: child.label.uppercased(),
                        subtitle: TextTools.count(child.threadIDs.count, singular: "THREAD", plural: "THREADS"),
                        provider: nil,
                        colorSeed: rootIndex,
                        priority: rootIndex,
                        parentID: regionID,
                        threadIDs: child.threadIDs,
                        cost: costByLeaf[child.id] ?? 0
                    ))
                    for threadID in child.threadIDs {
                        groupIDByThread[threadID] = childID
                    }
                }
            }

            // Defensive: a thread whose profile referenced an unknown topic
            // still needs a home on the map.
            let assignedRegion = Set(groupIDByThread.keys)
            let orphans = limited.filter { !assignedRegion.contains($0.id) }
            if !orphans.isEmpty {
                let regionID = "region:emerging"
                if !groups.contains(where: { $0.id == regionID }) {
                    groups.append(GroupSpec(
                        id: regionID,
                        label: "EMERGING",
                        subtitle: TextTools.count(orphans.count, singular: "THREAD", plural: "THREADS"),
                        provider: nil,
                        colorSeed: roots.count,
                        priority: 99,
                        parentID: nil,
                        threadIDs: [],
                        displayWeight: Double(orphans.count),
                        cost: orphans.reduce(0) { $0 + $1.totalCost }
                    ))
                }
                let childID = "region:emerging/misc"
                groups.append(GroupSpec(
                    id: childID,
                    label: "MISCELLANEOUS",
                    subtitle: TextTools.count(orphans.count, singular: "THREAD", plural: "THREADS"),
                    provider: nil,
                    colorSeed: roots.count,
                    priority: 99,
                    parentID: regionID,
                    threadIDs: orphans.map(\.id),
                    cost: orphans.reduce(0) { $0 + $1.totalCost }
                ))
                for thread in orphans { groupIDByThread[thread.id] = childID }
            }

        case .era:
            let buckets = eraBuckets(for: limited)
            for (offset, bucket) in buckets.enumerated() {
                let spec = GroupSpec(
                    id: "group:era:\(bucket.key)",
                    label: bucket.label,
                    subtitle: TextTools.count(bucket.threadIDs.count, singular: "THREAD", plural: "THREADS"),
                    provider: nil,
                    colorSeed: offset,
                    priority: offset,
                    parentID: nil,
                    threadIDs: bucket.threadIDs
                )
                groups.append(spec)
                for threadID in bucket.threadIDs { groupIDByThread[threadID] = spec.id }
            }
        }

        // Spend -------------------------------------------------------------
        // Region roots carry explicit profile costs; flat groups sum their
        // threads. The fallback also covers zero-cost region children.
        let threadByID = Dictionary(uniqueKeysWithValues: limited.map { ($0.id, $0) })
        for index in groups.indices where groups[index].cost == 0 {
            groups[index].cost = groups[index].threadIDs.reduce(0) {
                $0 + (threadByID[$1]?.totalCost ?? 0)
            }
        }

        // Tags --------------------------------------------------------------
        // Dense archives need stricter sharing: requiring three conversations
        // removes the long tail of one-off keyword pairs and keeps the map calm.
        let minimumTagThreads = limited.count >= 45 ? 3 : 2
        let tagLimit = limited.count >= 200 ? 90 : (limited.count >= 80 ? 60 : 42)
        var tagCounts: [String: Int] = [:]
        var tagScores: [String: Double] = [:]
        var tagsByThread: [String: [Keyword]] = [:]

        for thread in limited {
            let keywords = index.keywords(for: thread.id)
            var kept: [Keyword] = []
            for keyword in keywords where (index.documentFrequency[keyword.term] ?? 0) >= minimumTagThreads {
                kept.append(keyword)
                tagCounts[keyword.term, default: 0] += 1
                tagScores[keyword.term, default: 0] += keyword.score
            }
            tagsByThread[thread.id] = Array(kept.prefix(5))
        }

        // Cap very common tags so the map stays readable; keep the strongest.
        let tags = tagCounts.keys.sorted { a, b in
            let ac = tagCounts[a] ?? 0, bc = tagCounts[b] ?? 0
            if ac != bc { return ac > bc }
            return (tagScores[a] ?? 0) > (tagScores[b] ?? 0)
        }
        let allowedTags = Set(tags.prefix(tagLimit))

        // Nodes -------------------------------------------------------------
        var nodes: [MindMapNode] = []
        var edges: [MindMapEdge] = []

        nodes.append(rootNode(count: limited.count, groups: groups.count))

        for (index, group) in groups.enumerated() {
            nodes.append(MindMapNode(
                id: group.id,
                kind: .group,
                label: group.label,
                subtitle: group.subtitle,
                provider: group.provider,
                parentID: group.parentID,
                weight: group.displayWeight ?? Double(group.threadIDs.count),
                colorSeed: group.provider?.order ?? (group.colorSeed + 1) % 12,
                cost: group.cost,
                tokenCount: group.threadIDs.compactMap { threadByID[$0]?.tokenCount }.reduce(0, +)
            ))
            let edgeWeight = Double(max(1, group.threadIDs.count))
            if let parentID = group.parentID {
                edges.append(MindMapEdge(
                    source: parentID,
                    target: group.id,
                    kind: .regionGroup,
                    weight: edgeWeight
                ))
            } else {
                edges.append(MindMapEdge(
                    source: "root",
                    target: group.id,
                    kind: .rootGroup,
                    weight: max(edgeWeight, group.displayWeight ?? 0)
                ))
            }

            for threadID in group.threadIDs {
                guard let thread = limited.first(where: { $0.id == threadID }) else { continue }
                let nodeID = "thread:\(thread.id)"
                nodes.append(MindMapNode(
                    id: nodeID,
                    kind: .thread,
                    label: thread.title,
                    subtitle: thread.model ?? thread.provider.displayName,
                    provider: thread.provider,
                    groupID: group.id,
                    threadID: thread.id,
                    weight: 1.0 + min(3.0, log(1.0 + Double(thread.messageCount)) * 0.55),
                    colorSeed: group.provider?.order ?? (index % 12),
                    cost: thread.totalCost,
                    tokenCount: thread.tokenCount
                ))
                edges.append(MindMapEdge(
                    source: group.id,
                    target: nodeID,
                    kind: .groupThread,
                    weight: 1.0 + min(2.0, Double(thread.messageCount) / 40.0)
                ))

                if filters.includeTags {
                    for keyword in tagsByThread[thread.id] ?? [] where allowedTags.contains(keyword.term) {
                        let tagID = "tag:\(TextTools.slug(keyword.term))"
                        if !nodes.contains(where: { $0.id == tagID }) {
                            nodes.append(MindMapNode(
                                id: tagID,
                                kind: .tag,
                                label: keyword.term,
                                subtitle: nil,
                                weight: Double(tagCounts[keyword.term] ?? 1),
                                colorSeed: index % 12
                            ))
                        }
                        edges.append(MindMapEdge(
                            source: nodeID,
                            target: tagID,
                            kind: .threadTag,
                            weight: min(1.0, keyword.score / 12.0)
                        ))
                    }
                }
            }
        }

        // If tags are on, remove any tag node that got no edges (defensive).
        if filters.includeTags {
            let connected = Set(edges.filter { $0.kind == .threadTag }.flatMap { [$0.source, $0.target] })
            nodes.removeAll { $0.kind == .tag && !connected.contains($0.id) }
        }

        // Preserve group order, then threads by group/weight, then tags.
        let kindOrder: [NodeKind: Int] = [.root: 0, .group: 1, .thread: 2, .tag: 3]
        nodes.sort { a, b in
            let ka = kindOrder[a.kind] ?? 9, kb = kindOrder[b.kind] ?? 9
            if ka != kb { return ka < kb }
            if a.kind == .group {
                let pa = groups.firstIndex(where: { $0.id == a.id }) ?? 0
                let pb = groups.firstIndex(where: { $0.id == b.id }) ?? 0
                return pa < pb
            }
            return a.label.localizedStandardCompare(b.label) == .orderedAscending
        }

        let messages = limited.reduce(0) { $0 + $1.messageCount }
        let characters = limited.reduce(0) { $0 + $1.characterCount }
        let stats = GraphStats(
            threadCount: limited.count,
            messageCount: messages,
            tagCount: nodes.filter { $0.kind == .tag }.count,
            groupCount: groups.count,
            characterCount: characters,
            earliest: limited.map(\.createdAt).min(),
            latest: limited.map(\.updatedAt).max(),
            unfilteredThreadCount: library.threads.count,
            totalCost: limited.reduce(0) { $0 + $1.totalCost },
            costThreadCount: limited.filter(\.hasCostData).count
        )

        return MindMapGraph(
            nodes: nodes,
            edges: edges,
            stats: stats,
            filters: filters,
            keywordsByThread: tagsByThread
        )
    }

    // MARK: - Groups

    private struct GroupSpec {
        var id: String
        var label: String
        var subtitle: String
        var provider: Provider?
        var colorSeed: Int
        var priority: Int
        var parentID: String?
        var threadIDs: [String]
        /// Weight for container groups that do not own thread nodes directly.
        var displayWeight: Double? = nil
        var cost: Double = 0
    }

    private struct EraBucket {
        var key: String
        var label: String
        var threadIDs: [String]
        var sortDate: Date
    }

    /// Region grouping needs the topic pipeline. The app passes a cached,
    /// background-built analysis; tests and previews get a deterministic
    /// inline run for the filtered threads only.
    private static func regionAnalysis(
        for threads: [ConversationThread],
        provided: TopicAnalysis?
    ) -> TopicAnalysis {
        if let provided, !provided.profiles.isEmpty {
            return provided
        }
        return TopicPipeline().analyze(ThreadLibrary(threads: threads))
    }

    private static func rootNode(count: Int, groups: Int) -> MindMapNode {
        MindMapNode(
            id: "root",
            kind: .root,
            label: "MINDME",
            subtitle: count == 0
                ? "NO SIGNAL"
                : "\(TextTools.count(count, singular: "THREAD", plural: "THREADS")) · \(TextTools.count(groups, singular: "CONSTELLATION", plural: "CONSTELLATIONS"))"
        )
    }

    private static func eraBuckets(for threads: [ConversationThread]) -> [EraBucket] {
        let dates = threads.map(\.updatedAt)
        guard let earliest = dates.min(), let latest = dates.max() else { return [] }
        let span = latest.timeIntervalSince(earliest)
        let calendar = Calendar(identifier: .gregorian)

        if span < 60 * 60 * 24 * 130 {
            // Monthly buckets.
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM yy"
            var byKey: [String: [ConversationThread]] = [:]
            var dateByKey: [String: Date] = [:]
            for thread in threads {
                let comps = calendar.dateComponents([.year, .month], from: thread.updatedAt)
                let key = String(format: "y%04d-m%02d", comps.year ?? 0, comps.month ?? 0)
                byKey[key, default: []].append(thread)
                if dateByKey[key] == nil {
                    dateByKey[key] = calendar.date(from: comps) ?? thread.updatedAt
                }
            }
            return byKey.keys.sorted().compactMap { key in
                guard let items = byKey[key], let date = dateByKey[key] else { return nil }
                return EraBucket(
                    key: key,
                    label: formatter.string(from: date).uppercased(),
                    threadIDs: items.map(\.id),
                    sortDate: date
                )
            }
        }

        if span < 60 * 60 * 24 * 365 * 4 {
            // Quarterly buckets.
            var byKey: [String: [ConversationThread]] = [:]
            var dateByKey: [String: Date] = [:]
            for thread in threads {
                let comps = calendar.dateComponents([.year, .month], from: thread.updatedAt)
                let month = comps.month ?? 1
                let quarter = (month - 1) / 3 + 1
                let key = String(format: "y%04d-q%d", comps.year ?? 0, quarter)
                byKey[key, default: []].append(thread)
                if dateByKey[key] == nil {
                    var start = DateComponents()
                    start.year = comps.year
                    start.month = (quarter - 1) * 3 + 1
                    dateByKey[key] = calendar.date(from: start) ?? thread.updatedAt
                }
            }
            return byKey.keys.sorted().compactMap { key in
                guard let items = byKey[key], let date = dateByKey[key] else { return nil }
                let comps = calendar.dateComponents([.year, .month], from: date)
                let quarter = ((comps.month ?? 1) - 1) / 3 + 1
                let year = String(format: "%02d", (comps.year ?? 0) % 100)
                return EraBucket(
                    key: key,
                    label: "Q\(quarter) · \(year)",
                    threadIDs: items.map(\.id),
                    sortDate: date
                )
            }
        }

        var byYear: [String: [ConversationThread]] = [:]
        for thread in threads {
            let year = calendar.component(.year, from: thread.updatedAt)
            byYear[String(year), default: []].append(thread)
        }
        return byYear.keys.sorted().compactMap { year in
            guard let items = byYear[year] else { return nil }
            return EraBucket(
                key: "y\(year)",
                label: year,
                threadIDs: items.map(\.id),
                sortDate: items.map(\.updatedAt).min() ?? Date()
            )
        }
    }
}
