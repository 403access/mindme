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
                var p = hub + direction * cloudRadius * jitter(node.id, minimum: 0.78, maximum: 1.24)
                p += outward * 18
                if p.length < minRadius {
                    p = p.normalized * minRadius
                }
                anchors[node.id] = p
            }
        }

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

        return anchors
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
