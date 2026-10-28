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

        // Allocate an angular sector proportional to each group's size.
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
            let hub = Vec2(cos(hubAngle), sin(hubAngle)) * hubRadius
            anchors[group.id] = hub

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

        // Tags float between the conversations that share them.
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

        // A slightly elliptical field uses wide desktop canvases better than a
        // perfect circle, while keeping the radial hierarchy intact.
        for (id, point) in anchors where id != "root" {
            anchors[id] = Vec2(point.x * 1.12, point.y * 0.94)
        }

        return anchors
    }
}
