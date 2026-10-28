import Foundation

/// Deterministic 3D anchors. Groups sit on a sphere around the root, each
/// conversation cloud orbits its group hub, and shared tags bridge the clouds.
public enum GraphLayout3D {

    public static func anchors(for graph: MindMapGraph) -> [String: Vec3] {
        guard !graph.isEmpty else { return ["root": .zero] }

        var anchors: [String: Vec3] = ["root": .zero]
        let groups = graph.groupNodes
        guard !groups.isEmpty else { return anchors }

        let threads = graph.threadNodes
        let totalThreads = max(1, threads.count)
        let hubRadius = 330.0 + 7.0 * sqrt(Double(totalThreads))

        if groups.contains(where: { $0.parentID != nil }) {
            placeHierarchy(
                groups: groups,
                threads: threads,
                hubRadius: hubRadius,
                anchors: &anchors
            )
        } else {
            placeFlat(
                groups: groups,
                threads: threads,
                hubRadius: hubRadius,
                anchors: &anchors
            )
        }

        placeTags(graph: graph, hubRadius: hubRadius, anchors: &anchors)
        return anchors
    }

    // MARK: - Flat groups

    private static func placeFlat(
        groups: [MindMapNode],
        threads: [MindMapNode],
        hubRadius: Double,
        anchors: inout [String: Vec3]
    ) {
        // Groups on a Fibonacci sphere so every provider/topic gets its own
        // corner of space instead of sharing a flat ring.
        for (index, group) in groups.enumerated() {
            let direction = fibonacciDirection(index: index, count: groups.count)
            let hub = direction * hubRadius
            anchors[group.id] = hub

            let children = threads
                .filter { $0.groupID == group.id }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            let count = max(1, children.count)
            let cloudRadius = 100.0 + 9.0 * sqrt(Double(count))
            let outward = hub.normalized
            let minRadius = hubRadius * 0.42

            for (childIndex, node) in children.enumerated() {
                let direction = fibonacciDirection(index: childIndex, count: count)
                var point = hub + direction * cloudRadius * jitter(node.id, minimum: 0.78, maximum: 1.24)
                point += outward * 18
                if point.length < minRadius {
                    point = point.normalized * minRadius
                }
                anchors[node.id] = point
            }
        }
    }

    // MARK: - Hierarchical regions

    private static func placeHierarchy(
        groups: [MindMapNode],
        threads: [MindMapNode],
        hubRadius: Double,
        anchors: inout [String: Vec3]
    ) {
        let roots = groups.filter { $0.parentID == nil }
        guard !roots.isEmpty else { return }

        for (rootIndex, root) in roots.enumerated() {
            let rootDirection = fibonacciDirection(index: rootIndex, count: roots.count)
            let rootHub = rootDirection * (hubRadius * 0.55)
            anchors[root.id] = rootHub

            let children = groups.filter { $0.parentID == root.id }
            for (childIndex, child) in children.enumerated() {
                let offset = fibonacciDirection(index: childIndex + 1, count: max(children.count + 2, 3))
                let childDirection = (rootDirection + offset * 0.95).normalized
                let childHub = childDirection * (hubRadius * 1.02)
                anchors[child.id] = childHub

                let clouds = threads
                    .filter { $0.groupID == child.id }
                    .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
                let count = max(1, clouds.count)
                let cloudRadius = 78.0 + 8.0 * sqrt(Double(count))
                for (threadIndex, node) in clouds.enumerated() {
                    let direction = fibonacciDirection(index: threadIndex, count: count)
                    var point = childHub + direction * cloudRadius * jitter(node.id, minimum: 0.8, maximum: 1.2)
                    point += childDirection * 16
                    if point.length < hubRadius * 0.35 {
                        point = point.normalized * (hubRadius * 0.35)
                    }
                    anchors[node.id] = point
                }
            }
        }
    }

    // MARK: - Tags

    private static func placeTags(
        graph: MindMapGraph,
        hubRadius: Double,
        anchors: inout [String: Vec3]
    ) {
        // Tags float between the conversations that share them.
        let neighbors = graph.adjacency
        for tag in graph.tagNodes {
            let connected = (neighbors[tag.id] ?? []).compactMap { anchors[$0] }
            guard !connected.isEmpty else {
                anchors[tag.id] = fibonacciDirection(
                    index: Int(StableID.hash(tag.id) % 997),
                    count: 997
                ) * (hubRadius * 0.8)
                continue
            }
            var average = connected.reduce(Vec3.zero, +) / Double(connected.count)
            let seed = StableID.hash(tag.id)
            let direction = fibonacciDirection(index: Int(seed % 991), count: 991)
            average += direction * 26
            if average.length < hubRadius * 0.38 {
                average = average.normalized * (hubRadius * 0.38)
            }
            anchors[tag.id] = average
        }
    }

    // MARK: - Helpers

    private static func fibonacciDirection(index: Int, count: Int) -> Vec3 {
        let n = max(1, count)
        let y = 1.0 - 2.0 * (Double(index) + 0.5) / Double(n)
        let radius = sqrt(max(0, 1.0 - y * y))
        let theta = Double(index) * 2.399_963_229_728_653 // golden angle
        return Vec3(radius * cos(theta), y, radius * sin(theta)).normalized
    }

    private static func jitter(_ id: String, minimum: Double, maximum: Double) -> Double {
        let hash = StableID.hash(id)
        let unit = Double(hash % 10_000) / 10_000.0
        return minimum + (maximum - minimum) * unit
    }
}
