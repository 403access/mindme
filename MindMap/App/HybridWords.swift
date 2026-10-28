import SwiftUI
import AppKit
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
        words
            .filter { $0.rect.insetBy(dx: -5, dy: -4).contains(point) }
            .min { ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height) }
    }

    static func make(
        graph: MindMapGraph,
        projection: MapProjection,
        size: CGSize
    ) -> HybridWordLayout {
        let tags = graph.tagNodes
        guard !tags.isEmpty, size.width > 80, size.height > 80 else {
            return HybridWordLayout(size: size)
        }

        let adjacency = graph.adjacency
        let nodeByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let sorted = tags.sorted { a, b in
            if abs(a.weight - b.weight) > 0.0001 { return a.weight > b.weight }
            return a.label.localizedStandardCompare(b.label) == .orderedAscending
        }

        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
        guard bounds.width > 60, bounds.height > 60 else {
            return HybridWordLayout(size: size)
        }

        let minFont: CGFloat = 8.5
        let maxFont = min(max(20, min(size.width, size.height) * 0.052), 38)
        let minWeight = sorted.map(\.weight).min() ?? 0
        let maxWeight = sorted.map(\.weight).max() ?? 1
        let visibleBounds = bounds.insetBy(dx: -48, dy: -48)

        var occupied: [CGRect] = []
        var words: [CloudWord] = []

        for (rank, node) in sorted.enumerated() {
            guard let projected = projection.project(nodeID: node.id) else { continue }
            let anchor = projected.point
            guard visibleBounds.contains(anchor) else { continue }

            let rankNorm = sorted.count <= 1
                ? 1.0
                : Double(sorted.count - 1 - rank) / Double(sorted.count - 1)
            let weightNorm = maxWeight > minWeight
                ? (node.weight - minWeight) / (maxWeight - minWeight)
                : 0.5
            let blend = 0.68 * weightNorm + 0.32 * rankNorm
            let font = minFont + (maxFont - minFont) * CGFloat(pow(blend, 0.82))

            let term = KeywordExtractor.prettyLabel(node.label)
            let providerSet = Set((adjacency[node.id] ?? []).compactMap { nodeByID[$0]?.provider })
            let providers = providerSet.sorted { $0.order < $1.order }
            let color = WordCloudLayout.cloudColor(term: term, providers: providers)

            guard let placement = place(
                term: term,
                preferredFont: font,
                anchor: anchor,
                bounds: bounds,
                occupied: occupied,
                phase: Double(StableID.hash(node.id) % 6_283) / 1_000
            ) else { continue }

            let rect = CGRect(
                x: placement.point.x - placement.size.width / 2,
                y: placement.point.y - placement.size.height / 2,
                width: placement.size.width,
                height: placement.size.height
            )
            occupied.append(rect.insetBy(dx: -4, dy: -3))
            words.append(CloudWord(
                id: node.id,
                term: term,
                weight: node.weight,
                threadCount: max(1, Int(node.weight.rounded())),
                providers: providers,
                fontSize: placement.font,
                rect: rect,
                anchor: anchor,
                color: color
            ))
        }

        return HybridWordLayout(words: words, size: size)
    }

    private static func place(
        term: String,
        preferredFont: CGFloat,
        anchor: CGPoint,
        bounds: CGRect,
        occupied: [CGRect],
        phase: Double
    ) -> (point: CGPoint, size: CGSize, font: CGFloat)? {
        let scales: [CGFloat] = [1.0, 0.88, 0.76, 0.64, 0.54]
        for scale in scales {
            var font = preferredFont * scale
            guard font >= 8 else { continue }

            var textSize = WordCloudLayout.measure(term, font: font)
            let maxWidth = bounds.width * 0.82
            if textSize.width + 14 > maxWidth {
                font *= maxWidth / (textSize.width + 14)
                guard font >= 8 else { continue }
                textSize = WordCloudLayout.measure(term, font: font)
            }

            let wordSize = CGSize(width: ceil(textSize.width) + 14, height: ceil(textSize.height) + 8)
            guard wordSize.width <= bounds.width, wordSize.height <= bounds.height else { continue }
            guard let point = anchoredPoint(
                anchor: anchor,
                size: wordSize,
                bounds: bounds,
                occupied: occupied,
                phase: phase
            ) else { continue }
            return (point, wordSize, font)
        }
        return nil
    }

    private static func anchoredPoint(
        anchor: CGPoint,
        size: CGSize,
        bounds: CGRect,
        occupied: [CGRect],
        phase: Double
    ) -> CGPoint? {
        func fits(_ point: CGPoint) -> Bool {
            let rect = CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            guard bounds.contains(rect) else { return false }
            return !occupied.contains { $0.intersects(rect) }
        }

        if fits(anchor) { return anchor }

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
            if fits(point) { return point }
            angle += angleStep
            radius += radiusStep
        }
        return nil
    }
}

// MARK: - Hybrid renderer

struct HybridWordRenderer {
    let graph: MindMapGraph
    let layout: HybridWordLayout
    let selectedNodeID: String?
    let hoveredNodeID: String?

    func draw(into context: inout GraphicsContext) {
        guard layout.size.width > 0 else { return }
        let focusID = selectedNodeID ?? hoveredNodeID
        let focusPath = graph.focusPath(for: focusID)

        for word in layout.words {
            let selected = word.id == selectedNodeID
            let hovered = word.id == hoveredNodeID
            let dimmed = focusID != nil && !focusPath.contains(word.id)
            let alpha = dimmed ? 0.16 : (selected || hovered ? 1.0 : 0.9)
            let color = selected || hovered ? HUD.text : word.color

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
                    with: .color(HUD.void.opacity(selected || hovered ? 0.78 : 0.44))
                )
            }

            var textContext = context
            textContext.addFilter(.shadow(color: .black.opacity(0.92), radius: 3, x: 0, y: 1))

            if selected || hovered {
                var glow = textContext
                glow.addFilter(.shadow(
                    color: word.color.opacity(selected ? 0.85 : 0.55),
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
                    with: .color(word.color.opacity(selected ? 0.7 : 0.45)),
                    lineWidth: 0.9
                )
            } else {
                textContext.draw(resolved, at: word.center, anchor: .center)
            }
        }
    }
}
