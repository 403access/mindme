import SwiftUI
import MindMapCore

// MARK: - Hybrid layout

/// A word cloud anchored to the constellation. Every word starts at its tag
/// node's projected position and is nudged outward only as far as needed to
/// avoid collisions, so the map's structure remains visible.
struct HybridWordLayout {
    var words: [CloudWord]
    var size: CGSize

    init(words: [CloudWord] = [], size: CGSize = .zero) {
        self.words = words
        self.size = size
    }

    static let empty = HybridWordLayout()

    func word(at point: CGPoint) -> CloudWord? {
        var best: CloudWord?
        var bestArea = CGFloat.infinity
        for word in words {
            guard word.rect.insetBy(dx: -5, dy: -4).contains(point) else { continue }
            let area = word.rect.width * word.rect.height
            if area < bestArea {
                bestArea = area
                best = word
            }
        }
        return best
    }
}

// MARK: - Cached inputs

/// Everything about one tag that does not depend on the projection or canvas
/// size. Building these once per graph keeps keyword extraction, provider
/// resolution, and colour hashing out of the per-frame path.
private struct HybridWordSeed {
    let id: String
    let term: String
    let weight: Double
    let threadCount: Int
    let providers: [Provider]
    let color: Color
    let rankNorm: Double
    let phase: Double
}

/// One font step for a seed at the current canvas size, with its text already
/// measured. Panning and zooming reuse these boxes instead of re-measuring.
private struct HybridWordMetrics {
    let font: CGFloat
    let size: CGSize
}

/// Spatial hash for placed word rects. The hybrid layout used to compare every
/// candidate position against every placed word; the grid keeps each test local
/// even while the whole constellation is settling.
private struct OccupancyGrid {
    private static let cellSize: CGFloat = 64

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    private var buckets: [Cell: [CGRect]] = [:]

    mutating func insert(_ rect: CGRect) {
        for cell in cells(for: rect) {
            buckets[cell, default: []].append(rect)
        }
    }

    func intersects(_ rect: CGRect) -> Bool {
        for cell in cells(for: rect) {
            guard let bucket = buckets[cell] else { continue }
            if bucket.contains(where: { $0.intersects(rect) }) { return true }
        }
        return false
    }

    private func cells(for rect: CGRect) -> [Cell] {
        let size = Self.cellSize
        let minX = Int(floor(rect.minX / size))
        let maxX = Int(floor(rect.maxX / size))
        let minY = Int(floor(rect.minY / size))
        let maxY = Int(floor(rect.maxY / size))
        var result: [Cell] = []
        result.reserveCapacity((maxX - minX + 1) * (maxY - minY + 1))
        for x in minX...maxX {
            for y in minY...maxY {
                result.append(Cell(x: x, y: y))
            }
        }
        return result
    }
}

// MARK: - Layout cache

/// Memoizes the hybrid layout at three levels: graph-derived seeds, per-size
/// text metrics, and the final placed layout keyed by the projection state.
///
/// Drawing, hover hit testing, and click handling share one instance, so the
/// collision pass runs at most once per rendered frame — and not at all while
/// the camera is still (ambient motion at 10 fps costs only a key comparison).
final class HybridLayoutCache {
    private struct LayoutKey: Equatable {
        var graphRevision: Int
        var size: CGSize
        var projectionSize: CGSize
        var camera: Camera
        var camera3D: Camera3D
        var modeBlend: Double
        var positionEpoch: Int
    }

    private var seedRevision = -1
    private var seeds: [HybridWordSeed] = []
    private var minWeight: Double = 0
    private var maxWeight: Double = 1

    private var metricsSize: CGSize = .zero
    private var metricsBySeed: [[HybridWordMetrics]] = []

    private var layoutKey: LayoutKey?
    private var cachedLayout = HybridWordLayout.empty

    func layout(
        graph: MindMapGraph,
        graphRevision: Int,
        projection: MapProjection,
        size: CGSize,
        positionEpoch: Int
    ) -> HybridWordLayout {
        guard size.width > 80, size.height > 80 else {
            return HybridWordLayout(size: size)
        }

        if graphRevision != seedRevision {
            rebuildSeeds(graph)
            seedRevision = graphRevision
        }
        guard !seeds.isEmpty else {
            layoutKey = nil
            cachedLayout = HybridWordLayout(size: size)
            return cachedLayout
        }

        // Text metrics only depend on the graph and the canvas size, so a pan,
        // zoom, or orbit never pays for font measurement.
        if metricsSize != size {
            rebuildMetrics(size: size)
            metricsSize = size
        }

        let key = LayoutKey(
            graphRevision: graphRevision,
            size: size,
            projectionSize: projection.size,
            camera: projection.camera,
            camera3D: projection.camera3D,
            modeBlend: projection.modeBlend,
            positionEpoch: positionEpoch
        )
        if key == layoutKey { return cachedLayout }

        let placed = Self.place(
            seeds: seeds,
            metricsBySeed: metricsBySeed,
            projection: projection,
            size: size
        )
        layoutKey = key
        cachedLayout = placed
        return placed
    }

    // MARK: Seeds

    private func rebuildSeeds(_ graph: MindMapGraph) {
        let tags = graph.tagNodes
        guard !tags.isEmpty else {
            seeds = []
            metricsBySeed = []
            metricsSize = .zero
            return
        }

        let adjacency = graph.adjacency
        let nodeByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let sorted = tags.sorted { a, b in
            if abs(a.weight - b.weight) > 0.0001 { return a.weight > b.weight }
            return a.label.localizedStandardCompare(b.label) == .orderedAscending
        }

        minWeight = sorted.last?.weight ?? 0
        maxWeight = sorted.first?.weight ?? 1

        seeds = sorted.enumerated().map { rank, node in
            let rankNorm = sorted.count <= 1
                ? 1.0
                : Double(sorted.count - 1 - rank) / Double(sorted.count - 1)
            let term = KeywordExtractor.prettyLabel(node.label)
            let providerSet = Set((adjacency[node.id] ?? []).compactMap { nodeByID[$0]?.provider })
            let providers = providerSet.sorted { $0.order < $1.order }
            return HybridWordSeed(
                id: node.id,
                term: term,
                weight: node.weight,
                threadCount: max(1, Int(node.weight.rounded())),
                providers: providers,
                color: WordCloudLayout.cloudColor(term: term, providers: providers),
                rankNorm: rankNorm,
                phase: Double(StableID.hash(node.id) % 6_283) / 1_000
            )
        }

        metricsBySeed = []
        metricsSize = .zero
    }

    // MARK: Metrics

    private func rebuildMetrics(size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
        guard bounds.width > 60, bounds.height > 60 else {
            metricsBySeed = []
            return
        }

        let minFont: CGFloat = 8.5
        let maxFont = min(max(20, min(size.width, size.height) * 0.052), 38)
        let span = maxWeight - minWeight

        metricsBySeed = seeds.map { seed in
            let weightNorm = span > 0 ? (seed.weight - minWeight) / span : 0.5
            let blend = 0.68 * weightNorm + 0.32 * seed.rankNorm
            let font = minFont + (maxFont - minFont) * CGFloat(pow(blend, 0.82))
            return Self.metrics(term: seed.term, preferredFont: font, bounds: bounds)
        }
    }

    private static func metrics(
        term: String,
        preferredFont: CGFloat,
        bounds: CGRect
    ) -> [HybridWordMetrics] {
        let maxWidth = bounds.width * 0.82
        var result: [HybridWordMetrics] = []
        result.reserveCapacity(5)

        for scale in [CGFloat(1.0), 0.88, 0.76, 0.64, 0.54] {
            var font = preferredFont * scale
            guard font >= 8 else { continue }

            var textSize = WordCloudLayout.measure(term, font: font)
            if textSize.width + 14 > maxWidth {
                font *= maxWidth / (textSize.width + 14)
                guard font >= 8 else { continue }
                textSize = WordCloudLayout.measure(term, font: font)
            }

            let wordSize = CGSize(
                width: ceil(textSize.width) + 14,
                height: ceil(textSize.height) + 8
            )
            guard wordSize.width <= bounds.width, wordSize.height <= bounds.height else { continue }
            result.append(HybridWordMetrics(font: font, size: wordSize))
        }

        return result
    }

    // MARK: Placement

    private static func place(
        seeds: [HybridWordSeed],
        metricsBySeed: [[HybridWordMetrics]],
        projection: MapProjection,
        size: CGSize
    ) -> HybridWordLayout {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
        guard bounds.width > 60, bounds.height > 60,
              metricsBySeed.count == seeds.count else {
            return HybridWordLayout(size: size)
        }

        let visibleBounds = bounds.insetBy(dx: -48, dy: -48)
        var occupancy = OccupancyGrid()
        var words: [CloudWord] = []
        words.reserveCapacity(seeds.count)

        for (index, seed) in seeds.enumerated() {
            let metrics = metricsBySeed[index]
            guard !metrics.isEmpty else { continue }
            guard let projected = projection.project(nodeID: seed.id) else { continue }
            let anchor = projected.point
            guard visibleBounds.contains(anchor) else { continue }

            guard let placement = placeWord(
                anchor: anchor,
                metrics: metrics,
                bounds: bounds,
                occupancy: &occupancy,
                phase: seed.phase
            ) else { continue }

            let rect = CGRect(
                x: placement.point.x - placement.size.width / 2,
                y: placement.point.y - placement.size.height / 2,
                width: placement.size.width,
                height: placement.size.height
            )
            occupancy.insert(rect.insetBy(dx: -4, dy: -3))
            words.append(CloudWord(
                id: seed.id,
                term: seed.term,
                weight: seed.weight,
                threadCount: seed.threadCount,
                providers: seed.providers,
                fontSize: placement.font,
                rect: rect,
                anchor: anchor,
                color: seed.color
            ))
        }

        return HybridWordLayout(words: words, size: size)
    }

    private static func placeWord(
        anchor: CGPoint,
        metrics: [HybridWordMetrics],
        bounds: CGRect,
        occupancy: inout OccupancyGrid,
        phase: Double
    ) -> (point: CGPoint, size: CGSize, font: CGFloat)? {
        for metric in metrics {
            if let point = anchoredPoint(
                anchor: anchor,
                size: metric.size,
                bounds: bounds,
                occupancy: occupancy,
                phase: phase
            ) {
                return (point, metric.size, metric.font)
            }
        }
        return nil
    }

    private static func anchoredPoint(
        anchor: CGPoint,
        size: CGSize,
        bounds: CGRect,
        occupancy: OccupancyGrid,
        phase: Double
    ) -> CGPoint? {
        if fits(anchor, size: size, bounds: bounds, occupancy: occupancy) {
            return anchor
        }

        // Search outward from the tag node. The cap keeps words recognizably
        // attached to their place in the constellation.
        let maxRadius = min(bounds.width, bounds.height) * 0.30
        let radiusStep: CGFloat = 3.2
        let angleStep: CGFloat = 0.45
        var radius: CGFloat = radiusStep
        var angle = CGFloat(phase)

        while radius <= maxRadius {
            let point = CGPoint(
                x: anchor.x + cos(angle) * radius,
                y: anchor.y + sin(angle) * radius
            )
            if fits(point, size: size, bounds: bounds, occupancy: occupancy) {
                return point
            }
            angle += angleStep
            radius += radiusStep
        }
        return nil
    }

    private static func fits(
        _ point: CGPoint,
        size: CGSize,
        bounds: CGRect,
        occupancy: OccupancyGrid
    ) -> Bool {
        let rect = CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        guard bounds.contains(rect) else { return false }
        return !occupancy.intersects(rect)
    }
}

// MARK: - Hybrid renderer

struct HybridWordRenderer {
    let layout: HybridWordLayout
    let selectedNodeID: String?
    let hoveredNodeID: String?
    let focusPath: Set<String>
    var searchHighlightIDs: Set<String> = []
    var searchFocusActive: Bool = false

    func draw(into context: inout GraphicsContext) {
        guard layout.size.width > 0 else { return }
        let focusID = selectedNodeID ?? hoveredNodeID
        let searchDimming = searchFocusActive && focusID == nil && !searchHighlightIDs.isEmpty

        for word in layout.words {
            let selected = word.id == selectedNodeID
            let hovered = word.id == hoveredNodeID
            let matched = searchDimming && searchHighlightIDs.contains(word.id)
            let dimmed = (focusID != nil && !focusPath.contains(word.id))
                || (searchDimming && !matched)
            let alpha = dimmed ? 0.16 : (selected || hovered || matched ? 1.0 : 0.9)
            let color = selected || hovered || matched ? HUD.text : word.color

            // Faint tether back to the tag node when collision resolution has
            // moved the word away from its structural anchor.
            let displacement = hypot(word.center.x - word.anchor.x, word.center.y - word.anchor.y)
            if displacement > 9 {
                var tether = Path()
                tether.move(to: word.anchor)
                tether.addLine(to: word.center)
                context.stroke(
                    tether,
                    with: .color(word.color.opacity(dimmed ? 0.04 : 0.22)),
                    style: StrokeStyle(lineWidth: 0.7, dash: [2, 4])
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: word.anchor.x - 1.5,
                        y: word.anchor.y - 1.5,
                        width: 3,
                        height: 3
                    )),
                    with: .color(word.color.opacity(dimmed ? 0.08 : 0.45))
                )
            }

            let resolved = context.resolve(
                Text(word.term)
                    .font(.system(size: word.fontSize, weight: .semibold))
                    .foregroundColor(color.opacity(alpha))
            )

            if !dimmed {
                let plate = Path(
                    roundedRect: word.rect.insetBy(dx: -4, dy: -2),
                    cornerRadius: 4
                )
                context.fill(
                    plate,
                    with: .color(HUD.void.opacity(selected || hovered || matched ? 0.78 : 0.44))
                )
            }

            var textContext = context
            textContext.addFilter(.shadow(color: .black.opacity(0.92), radius: 3, x: 0, y: 1))

            if selected || hovered || matched {
                var glow = textContext
                glow.addFilter(.shadow(
                    color: (matched && !selected && !hovered ? HUD.amber : word.color)
                        .opacity(selected ? 0.85 : 0.55),
                    radius: selected ? 11 : 7
                ))
                glow.draw(resolved, at: word.center, anchor: .center)

                let underlineWidth = max(10, word.rect.width - 14)
                let underlineY = word.center.y + word.fontSize * 0.66
                var underline = Path()
                underline.move(to: CGPoint(x: word.center.x - underlineWidth / 2, y: underlineY))
                underline.addLine(to: CGPoint(x: word.center.x + underlineWidth / 2, y: underlineY))
                context.stroke(
                    underline,
                    with: .color((matched && !selected && !hovered ? HUD.amber : word.color)
                        .opacity(selected ? 0.7 : 0.45)),
                    lineWidth: 0.9
                )
            } else {
                textContext.draw(resolved, at: word.center, anchor: .center)
            }
        }
    }
}
