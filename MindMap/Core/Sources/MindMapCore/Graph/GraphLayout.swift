import Foundation

/// Deterministic radial anchors. The force simulation relaxes these into an
/// organic, clustered constellation while keeping the hierarchy legible.
public enum GraphLayout {

    public static func anchors(for graph: MindMapGraph) -> [String: Vec2] {
        guard !graph.isEmpty else { return ["root": .zero] }

        var anchors: [String: Vec2] = [:]
        anchors["root"] = .zero

        let groups = graph.groupNodes
        guard !groups.isEmpty else { return anchors }

        let threadNodes = graph.threadNodes
        let totalThreads = max(1, threadNodes.count)
        let hubRadius = 235.0 + 8.5 * sqrt(Double(totalThreads))

        if groups.contains(where: { $0.parentID != nil }) {
            placeHierarchy(
                groups: groups,
                threadNodes: threadNodes,
                hubRadius: hubRadius,
                anchors: &anchors
            )
        } else {
            placeFlat(
                groups: groups,
                threadNodes: threadNodes,
                hubRadius: hubRadius,
                anchors: &anchors
            )
        }

        // Tags float between the conversations that share them.
        placeTags(graph: graph, hubRadius: hubRadius, anchors: &anchors)

        // A slightly elliptical field uses wide desktop canvases better than a
        // perfect circle, while keeping the radial hierarchy intact.
        for (id, point) in anchors where id != "root" {
            anchors[id] = Vec2(point.x * 1.12, point.y * 0.94)
        }

        return anchors
    }

    // MARK: - Flat groups (provider / topic / era)

    private static func placeFlat(
        groups: [MindMapNode],
        threadNodes: [MindMapNode],
        hubRadius: Double,
        anchors: inout [String: Vec2]
    ) {
        var weights: [Double] = []
        for group in groups {
            let count = threadNodes.filter { $0.groupID == group.id }.count
            weights.append(Double(max(count, 2)))
        }
        let totalWeight = weights.reduce(0, +)
        let padding = groups.count > 1 ? 0.10 : 0.0
        let usable = 2 * Double.pi - padding * Double(groups.count)
        var angle = -Double.pi / 2

        for (groupIndex, group) in groups.enumerated() {
            let sector = usable * (weights[groupIndex] / totalWeight)
            let hubAngle = angle + sector / 2 + padding / 2
            anchors[group.id] = Vec2(cos(hubAngle), sin(hubAngle)) * hubRadius

            let children = threadNodes
                .filter { $0.groupID == group.id }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            // Dense groups get more columns per row; a single-source archive
            // then reads as a wide fountain instead of a narrow plume.
            let perRow = min(12, max(7, Int(ceil(sqrt(Double(children.count) * 1.4)))))
            let rows = max(1, Int(ceil(Double(children.count) / Double(perRow))))
            let spread = min(2.5, max(0.34, sector * 0.86))

            for (index, node) in children.enumerated() {
                let row = index / perRow
                let column = index % perRow
                let countInRow = min(perRow, children.count - row * perRow)
                let rowFraction = rows <= 1 ? 0.0 : Double(row) / Double(rows - 1)
                let radius = hubRadius + 74 + Double(row) * 54 + rowFraction * 8
                let t = countInRow <= 1 ? 0.5 : Double(column) / Double(countInRow - 1)
                let angularOffset = (t - 0.5) * spread * (1.0 - rowFraction * 0.12)
                let stagger = (row % 2 == 1) ? spread / Double(max(countInRow, 1)) * 0.35 : 0
                let nodeAngle = hubAngle + angularOffset + stagger
                anchors[node.id] = Vec2(cos(nodeAngle), sin(nodeAngle)) * radius
            }

            angle += sector + padding
        }
    }

    // MARK: - Hierarchical regions

    private static func placeHierarchy(
        groups: [MindMapNode],
        threadNodes: [MindMapNode],
        hubRadius: Double,
        anchors: inout [String: Vec2]
    ) {
        let roots = groups.filter { $0.parentID == nil }
        guard !roots.isEmpty else { return }

        let groupByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        func ownedThreads(_ rootID: String) -> [MindMapNode] {
            threadNodes.filter { node in
                guard let groupID = node.groupID,
                      let group = groupByID[groupID] else { return false }
                return groupID == rootID || group.parentID == rootID
            }
        }

        let weights = roots.map { Double(max(ownedThreads($0.id).count, 2)) }
        let totalWeight = weights.reduce(0, +)
        let padding = roots.count > 1 ? 0.10 : 0.0
        let usable = 2 * Double.pi - padding * Double(roots.count)
        var angle = -Double.pi / 2

        for (rootIndex, root) in roots.enumerated() {
            let sector = usable * (weights[rootIndex] / totalWeight)
            let rootAngle = angle + sector / 2 + padding / 2
            // Regions live on an inner ring; their sub-regions and threads
            // fan outward so the nesting reads inside-out.
            anchors[root.id] = Vec2(cos(rootAngle), sin(rootAngle)) * (hubRadius * 0.70)

            let children = groups.filter { $0.parentID == root.id }
            let spread = min(2.4, max(0.62, sector * 0.82))

            if children.isEmpty {
                let direct = ownedThreads(root.id)
                    .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
                placeThreads(
                    direct,
                    centerAngle: rootAngle,
                    baseRadius: hubRadius * 0.82,
                    spread: min(1.2, max(0.35, sector * 0.7)),
                    anchors: &anchors
                )
            }

            for (childIndex, child) in children.enumerated() {
                let t = children.count <= 1
                    ? 0.5
                    : Double(childIndex) / Double(children.count - 1)
                let childAngle = rootAngle + (t - 0.5) * spread
                let childRadius = hubRadius + 26
                anchors[child.id] = Vec2(cos(childAngle), sin(childAngle)) * childRadius

                let threads = threadNodes
                    .filter { $0.groupID == child.id }
                    .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
                let childSpread = min(1.15, max(0.30, sector / Double(max(children.count, 1)) * 0.82))
                placeThreads(
                    threads,
                    centerAngle: childAngle,
                    baseRadius: childRadius + 86,
                    spread: childSpread,
                    anchors: &anchors
                )
            }

            angle += sector + padding
        }
    }

    private static func placeThreads(
        _ threads: [MindMapNode],
        centerAngle: Double,
        baseRadius: Double,
        spread: Double,
        anchors: inout [String: Vec2]
    ) {
        guard !threads.isEmpty else { return }
        let perRow = min(8, max(5, Int(ceil(sqrt(Double(threads.count) * 1.3)))))
        let rows = max(1, Int(ceil(Double(threads.count) / Double(perRow))))
        for (index, node) in threads.enumerated() {
            let row = index / perRow
            let column = index % perRow
            let countInRow = min(perRow, threads.count - row * perRow)
            let rowFraction = rows <= 1 ? 0.0 : Double(row) / Double(rows - 1)
            let radius = baseRadius + Double(row) * 52 + rowFraction * 8
            let t = countInRow <= 1 ? 0.5 : Double(column) / Double(countInRow - 1)
            let nodeAngle = centerAngle + (t - 0.5) * spread * (1.0 - rowFraction * 0.12)
            anchors[node.id] = Vec2(cos(nodeAngle), sin(nodeAngle)) * radius
        }
    }

    // MARK: - Tags

    private static func placeTags(
        graph: MindMapGraph,
        hubRadius: Double,
        anchors: inout [String: Vec2]
    ) {
        let neighbors = graph.adjacency
        for tag in graph.tagNodes {
            let connected = (neighbors[tag.id] ?? []).compactMap { anchors[$0] }
            guard !connected.isEmpty else {
                let jitterAngle = Double(StableID.hash(tag.id) % 6283) / 1000.0
                anchors[tag.id] = Vec2(cos(jitterAngle), sin(jitterAngle)) * (hubRadius + 120)
                continue
            }
            var average = connected.reduce(Vec2.zero, +) / Double(connected.count)
            var outward = average.normalized
            if outward.length < 0.001 {
                let fallbackAngle = Double(StableID.hash(tag.id) % 6283) / 1000.0
                outward = Vec2(cos(fallbackAngle), sin(fallbackAngle))
            }
            let jitterSeed = StableID.hash(tag.id)
            let jitter = Double(jitterSeed % 360) / 180.0 * Double.pi
            let offset = Vec2(cos(jitter), sin(jitter)) * (32 + Double(jitterSeed % 26))
            average += outward * 34 + offset

            // Keep shared tags out of the root's inner sanctum. Averaging two
            // conversations on opposite sides otherwise parks tags on the logo.
            let minimumRadius = hubRadius + 58
            if average.length < minimumRadius {
                average = outward * minimumRadius
            }
            anchors[tag.id] = average
        }
    }
}
