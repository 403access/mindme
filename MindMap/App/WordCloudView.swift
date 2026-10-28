import SwiftUI
import AppKit
import MindMapCore

// MARK: - Layout

/// One placed keyword. Words are laid out once per graph/size change so that
/// hover hit testing and drawing share exactly the same geometry.
struct CloudWord: Identifiable {
    let id: String
    let term: String
    let weight: Double
    let threadCount: Int
    let providers: [Provider]
    let fontSize: CGFloat
    let rect: CGRect
    let color: Color

    var center: CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }
}

/// Deterministic spiral packing. The largest words land nearest the centre,
/// smaller words orbit outward, and anything that cannot fit is scaled down
/// before being dropped.
struct WordCloudLayout {
    var words: [CloudWord]
    var size: CGSize

    init(words: [CloudWord] = [], size: CGSize = .zero) {
        self.words = words
        self.size = size
    }

    static let empty = WordCloudLayout()

    func word(at point: CGPoint) -> CloudWord? {
        words
            .filter { $0.rect.insetBy(dx: -5, dy: -4).contains(point) }
            .min { ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height) }
    }

    static func make(graph: MindMapGraph, size: CGSize) -> WordCloudLayout {
        let tags = graph.tagNodes
        guard !tags.isEmpty, size.width > 80, size.height > 80 else {
            return WordCloudLayout(size: size)
        }

        let adjacency = graph.adjacency
        let nodeByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let sorted = tags.sorted { a, b in
            if abs(a.weight - b.weight) > 0.0001 { return a.weight > b.weight }
            return a.label.localizedStandardCompare(b.label) == .orderedAscending
        }

        let padding: CGFloat = 30
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: padding, dy: padding)
        guard bounds.width > 60, bounds.height > 60 else {
            return WordCloudLayout(size: size)
        }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let minFont: CGFloat = 10.5
        let maxFont = min(max(34, min(size.width, size.height) * 0.105), 76)
        let minWeight = sorted.map(\.weight).min() ?? 0
        let maxWeight = sorted.map(\.weight).max() ?? 1

        var occupied: [CGRect] = []
        var words: [CloudWord] = []

        for (rank, node) in sorted.enumerated() {
            let rankNorm = sorted.count <= 1
                ? 1.0
                : Double(sorted.count - 1 - rank) / Double(sorted.count - 1)
            let weightNorm = maxWeight > minWeight
                ? (node.weight - minWeight) / (maxWeight - minWeight)
                : 0.5
            // Mostly frequency-driven, with a little rank falloff so a batch of
            // equally-shared words still becomes a readable cloud.
            let blend = 0.68 * weightNorm + 0.32 * rankNorm
            let font = minFont + (maxFont - minFont) * CGFloat(pow(blend, 0.82))

            let term = KeywordExtractor.prettyLabel(node.label)
            let providerSet = Set((adjacency[node.id] ?? []).compactMap { nodeByID[$0]?.provider })
            let providers = providerSet.sorted { $0.order < $1.order }
            let color = cloudColor(term: term, providers: providers)

            guard let placement = place(
                term: term,
                preferredFont: font,
                bounds: bounds,
                center: center,
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
                color: color
            ))
        }

        return WordCloudLayout(words: words, size: size)
    }

    private static func cloudColor(term: String, providers: [Provider]) -> Color {
        if providers.count > 1 { return HUD.accent }
        if let provider = providers.first { return HUD.providerColor(provider) }
        return HUD.topicColor(seed: Int(StableID.hash(term) % 10_000))
    }

    private static func place(
        term: String,
        preferredFont: CGFloat,
        bounds: CGRect,
        center: CGPoint,
        occupied: [CGRect],
        phase: Double
    ) -> (point: CGPoint, size: CGSize, font: CGFloat)? {
        let scales: [CGFloat] = [1.0, 0.88, 0.76, 0.64, 0.54]
        for scale in scales {
            var font = preferredFont * scale
            guard font >= 8.5 else { continue }

            var textSize = measure(term, font: font)
            let maxWidth = bounds.width * 0.86
            if textSize.width + 14 > maxWidth {
                font *= maxWidth / (textSize.width + 14)
                guard font >= 8.5 else { continue }
                textSize = measure(term, font: font)
            }

            let wordSize = CGSize(width: ceil(textSize.width) + 14, height: ceil(textSize.height) + 8)
            guard wordSize.width <= bounds.width, wordSize.height <= bounds.height else { continue }
            guard let point = spiralPoint(size: wordSize, bounds: bounds, center: center, occupied: occupied, phase: phase) else {
                continue
            }
            return (point, wordSize, font)
        }
        return nil
    }

    private static func measure(_ term: String, font: CGFloat) -> CGSize {
        let nsFont = NSFont.systemFont(ofSize: font, weight: .semibold)
        return (term as NSString).size(withAttributes: [.font: nsFont])
    }

    private static func spiralPoint(
        size: CGSize,
        bounds: CGRect,
        center: CGPoint,
        occupied: [CGRect],
        phase: Double
    ) -> CGPoint? {
        // A slowly expanding ellipse: radius is a fraction of the canvas, so
        // wide maps fill horizontally instead of collapsing into a circle.
        var angle = CGFloat(phase)
        var progress: CGFloat = 0
        let angleStep: CGFloat = 0.24
        let progressStep: CGFloat = 0.002
        let maxSteps = 1_600

        for _ in 0..<maxSteps {
            let point = CGPoint(
                x: center.x + cos(angle) * progress * bounds.width / 2,
                y: center.y + sin(angle) * progress * bounds.height / 2
            )
            let rect = CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            if bounds.contains(rect), !occupied.contains(where: { $0.intersects(rect) }) {
                return point
            }
            angle += angleStep
            progress += progressStep
            if progress > 1.0 { return nil }
        }
        return nil
    }
}

// MARK: - Renderer

struct WordCloudRenderer {
    let layout: WordCloudLayout
    let selectedNodeID: String?
    let hoveredNodeID: String?
    let motion: Bool
    let time: Double

    func draw(into context: inout GraphicsContext) {
        guard layout.size.width > 0 else { return }
        drawField(&context)

        let focusID = selectedNodeID ?? hoveredNodeID
        for word in layout.words {
            let selected = word.id == selectedNodeID
            let hovered = word.id == hoveredNodeID
            let dimmed = focusID != nil && !selected && !hovered
            let alpha = dimmed ? 0.18 : (selected || hovered ? 1.0 : 0.88)
            let color = selected || hovered ? HUD.text : word.color
            let drift = motion
                ? sin(time * 0.7 + Double(StableID.hash(word.id) % 6_283) / 1_000) * 1.4
                : 0
            let point = CGPoint(x: word.center.x, y: word.center.y + drift)

            let resolved = context.resolve(
                Text(word.term)
                    .font(.system(size: word.fontSize, weight: .semibold))
                    .foregroundColor(color.opacity(alpha))
            )

            if selected || hovered {
                var glow = context
                glow.addFilter(.shadow(
                    color: word.color.opacity(selected ? 0.85 : 0.55),
                    radius: selected ? 12 : 7
                ))
                glow.draw(resolved, at: point, anchor: .center)

                let underlineWidth = max(10, word.rect.width - 14)
                let underlineY = point.y + word.fontSize * 0.66
                var underline = Path()
                underline.move(to: CGPoint(x: point.x - underlineWidth / 2, y: underlineY))
                underline.addLine(to: CGPoint(x: point.x + underlineWidth / 2, y: underlineY))
                context.stroke(
                    underline,
                    with: .color(word.color.opacity(selected ? 0.7 : 0.45)),
                    lineWidth: 0.9
                )
            } else {
                context.draw(resolved, at: point, anchor: .center)
            }
        }
    }

    private func drawField(_ context: inout GraphicsContext) {
        let size = layout.size
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let shortSide = min(size.width, size.height)
        guard shortSide > 40 else { return }

        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - shortSide * 0.48,
                y: center.y - shortSide * 0.48,
                width: shortSide * 0.96,
                height: shortSide * 0.96
            )),
            with: .radialGradient(
                Gradient(colors: [HUD.accent.opacity(0.05), HUD.accent.opacity(0.012), .clear]),
                center: center,
                startRadius: 0,
                endRadius: shortSide * 0.48
            )
        )

        for (index, factor) in [0.24, 0.44, 0.66].enumerated() {
            let radius = shortSide * factor
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(HUD.accent.opacity(index == 0 ? 0.075 : 0.038)),
                style: StrokeStyle(
                    lineWidth: 0.7,
                    dash: index == 0 ? [2, 10] : [1, 16],
                    dashPhase: motion ? time * (index % 2 == 0 ? 5 : -4) : 0
                )
            )
        }

        let tickRadius = shortSide * 0.24
        var ticks = Path()
        for tick in 0..<64 {
            let angle = Double(tick) / 64 * 2 * .pi + (motion ? time * 0.015 : 0)
            let inner = CGPoint(
                x: center.x + cos(angle) * tickRadius,
                y: center.y + sin(angle) * tickRadius
            )
            let outerRadius = tickRadius + (tick % 8 == 0 ? 7 : 3)
            let outer = CGPoint(
                x: center.x + cos(angle) * outerRadius,
                y: center.y + sin(angle) * outerRadius
            )
            ticks.move(to: inner)
            ticks.addLine(to: outer)
        }
        context.stroke(ticks, with: .color(HUD.accent.opacity(0.045)), lineWidth: 0.6)
    }
}

// MARK: - View

struct WordCloudView: View {
    @ObservedObject var model: AppModel

    @State private var layout = WordCloudLayout.empty
    @State private var hoveredWordID: String?
    @State private var hoverLocation: CGPoint?
    @State private var cursorIsHand = false

    private let mapCornerRadius: CGFloat = 18

    private var signature: String {
        model.graph.tagNodes
            .map { "\($0.id):\(Int($0.weight.rounded()))" }
            .joined(separator: "|")
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if !model.graph.isEmpty && !model.graph.tagNodes.isEmpty {
                    TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !model.motionEnabled)) { timeline in
                        Canvas(opaque: false, colorMode: .extendedLinear) { context, _ in
                            let renderer = WordCloudRenderer(
                                layout: layout,
                                selectedNodeID: model.selectedNodeID,
                                hoveredNodeID: hoveredWordID,
                                motion: model.motionEnabled,
                                time: timeline.date.timeIntervalSinceReferenceDate
                            )
                            renderer.draw(into: &context)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                if let word = layout.word(at: value.location) {
                                    model.select(word.id)
                                } else {
                                    model.deselect()
                                }
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverLocation = location
                            let word = layout.word(at: location)
                            if hoveredWordID != word?.id {
                                hoveredWordID = word?.id
                            }
                            setCursor(hand: word != nil)
                        case .ended:
                            hoverLocation = nil
                            hoveredWordID = nil
                            setCursor(hand: false)
                        }
                    }
                } else {
                    CloudEmptyState(model: model)
                }

                RadialGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.32)],
                    center: .center,
                    startRadius: min(size.width, size.height) * 0.24,
                    endRadius: max(size.width, size.height) * 0.72
                )
                .allowsHitTesting(false)
                .blendMode(.multiply)

                if !model.graph.isEmpty && !model.graph.tagNodes.isEmpty {
                    overlays(size: size)
                }

                if let location = hoverLocation,
                   let wordID = hoveredWordID,
                   let word = layout.words.first(where: { $0.id == wordID }) {
                    CloudHoverCard(word: word)
                        .fixedSize()
                        .position(
                            x: min(max(location.x + 18, 120), size.width - 120),
                            y: min(max(location.y + 20, 56), size.height - 80)
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: mapCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: mapCornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.11), HUD.accent.opacity(0.10), Color.white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .onAppear {
                rebuildLayout(size: size)
            }
            .onChange(of: size) { _, newSize in
                rebuildLayout(size: newSize)
            }
            .onChange(of: signature) { _, _ in
                rebuildLayout(size: size)
            }
            .onDisappear {
                hoveredWordID = nil
                hoverLocation = nil
                setCursor(hand: false)
            }
        }
    }

    private func rebuildLayout(size: CGSize) {
        layout = WordCloudLayout.make(graph: model.graph, size: size)
        if let hoveredWordID, layout.words.contains(where: { $0.id == hoveredWordID }) == false {
            self.hoveredWordID = nil
        }
    }

    private func overlay(_ systemName: String, text: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(text)
                    .font(HUDFont.micro(7.5))
                    .tracking(0.4)
            }
            .foregroundStyle(HUD.accent)
            .frame(width: 54, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(HUD.accent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(HUD.accent.opacity(0.45), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private func overlays(size: CGSize) -> some View {
        // Telemetry, top-left
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(HUD.accent)
                    .frame(width: 4.5, height: 4.5)
                    .shadow(color: HUD.accent.opacity(0.9), radius: 4)
                Text("SEMANTIC CLOUD")
                    .font(HUDFont.micro(8))
                    .tracking(1.4)
                    .foregroundStyle(HUD.textSoft)
                Text("·")
                    .foregroundStyle(HUD.dim)
                Text("\(Format.count(layout.words.count, "WORD", "WORDS")) / \(Format.count(model.graph.stats.threadCount, "THREAD", "THREADS"))")
                    .font(HUDFont.micro(8))
                    .tracking(0.8)
                    .foregroundStyle(HUD.muted)
            }

            if !model.searchText.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 7.5, weight: .bold))
                    Text("FILTER: \(model.searchText.uppercased())")
                        .font(HUDFont.micro(7.5))
                        .tracking(0.7)
                }
                .foregroundStyle(HUD.amber)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(HUD.amber.opacity(0.08))
                        .overlay(Capsule().strokeBorder(HUD.amber.opacity(0.3), lineWidth: 0.7))
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        // Mode switch, top-right
        VStack(spacing: 7) {
            overlay("point.3.connected.trianglepath.dotted", text: "MAP", help: "Back to the constellation  ⌘4") {
                model.showWordCloud = false
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

        // Legend, bottom-left
        HStack(spacing: 12) {
            Text("LARGER = MORE CONVERSATIONS · CLICK A WORD TO ISOLATE")
                .font(HUDFont.micro(7))
                .tracking(0.9)
                .foregroundStyle(HUD.dim.opacity(0.8))
            Rectangle().fill(HUD.hairline).frame(width: 1, height: 8)
            ForEach(Provider.allCases, id: \.self) { provider in
                if model.providers.contains(provider), model.providerCount(provider) > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(HUD.providerColor(provider)).frame(width: 4, height: 4)
                        Text(provider.shortName)
                            .font(HUDFont.micro(7.5))
                            .tracking(0.8)
                            .foregroundStyle(HUD.muted)
                    }
                }
            }
            HStack(spacing: 4) {
                Circle().fill(HUD.accent).frame(width: 4, height: 4)
                Text("SHARED")
                    .font(HUDFont.micro(7.5))
                    .tracking(0.8)
                    .foregroundStyle(HUD.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func setCursor(hand: Bool) {
        guard hand != cursorIsHand else { return }
        cursorIsHand = hand
        if hand {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

// MARK: - Hover card

struct CloudHoverCard: View {
    var word: CloudWord

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                ForEach(Array(word.providers.prefix(3)), id: \.self) { provider in
                    ProviderBadge(provider: provider, compact: true)
                }
                if word.providers.isEmpty {
                    MicroLabel(text: "SHARED KEYWORD", color: HUD.accent)
                }
                Spacer(minLength: 0)
                Text("×\(word.threadCount)")
                    .font(HUDFont.micro(7.5))
                    .foregroundStyle(HUD.textSoft)
            }
            Text(word.term)
                .font(HUDFont.display(14, weight: .medium))
                .foregroundStyle(HUD.text)
                .lineLimit(2)
                .frame(maxWidth: 210, alignment: .leading)
            HStack(spacing: 8) {
                Text(Format.count(word.threadCount, "CONVERSATION", "CONVERSATIONS"))
                    .font(HUDFont.micro(7))
                    .tracking(0.7)
                    .foregroundStyle(HUD.muted)
                Text("CLICK TO ISOLATE")
                    .font(HUDFont.micro(7))
                    .tracking(0.6)
                    .foregroundStyle(HUD.accent.opacity(0.8))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hex: 0x060C16).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(HUD.accent.opacity(0.28), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.55), radius: 14, y: 6)
        )
    }
}

// MARK: - Empty state

struct CloudEmptyState: View {
    var model: AppModel

    private var tagsOff: Bool { !model.showTags && model.hasThreads }
    private var hasWords: Bool { !model.graph.tagNodes.isEmpty }

    private var headline: String {
        if !model.hasThreads { return "NO SIGNAL" }
        if tagsOff { return "TAGS ARE OFF" }
        if !hasWords { return "NO SHARED WORDS" }
        return "NOTHING IN THIS WINDOW"
    }

    private var explanation: String {
        if !model.hasThreads {
            return "Import a conversation export to grow the word cloud.\nEverything stays on this Mac."
        }
        if tagsOff {
            return "The cloud is built from shared keyword tags.\nSwitch TAGS back on to see the lexical field."
        }
        if !model.searchText.isEmpty {
            return "No shared keyword matches “\(model.searchText)”.\nClear the query or widen the time window."
        }
        return "Words appear when at least two conversations share a keyword.\nWiden the filters or import more threads."
    }

    var body: some View {
        VStack(spacing: 17) {
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .strokeBorder(HUD.accent.opacity(0.18 - Double(index) * 0.045), lineWidth: 0.8)
                        .frame(width: CGFloat(92 + index * 34), height: CGFloat(92 + index * 34))
                }
                Image(systemName: tagsOff ? "cloud.slash" : "text.magnifyingglass")
                    .font(.system(size: 27, weight: .thin))
                    .foregroundStyle(HUD.accent.opacity(0.8))
            }

            VStack(spacing: 7) {
                Text(headline)
                    .font(HUDFont.label(15))
                    .tracking(3.4)
                    .foregroundStyle(HUD.text)
                Text(explanation)
                    .font(HUDFont.body(11.5))
                    .foregroundStyle(HUD.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            HStack(spacing: 9) {
                if tagsOff {
                    HUDPrimaryButton(title: "Enable tags", icon: "diamond") {
                        model.showTags = true
                    }
                    .frame(width: 154)
                } else if model.hasThreads {
                    HUDGhostButton(title: "Back to map", icon: "point.3.connected.trianglepath.dotted") {
                        model.showWordCloud = false
                    }
                } else {
                    HUDPrimaryButton(title: "Import exports", icon: "square.and.arrow.down") {
                        model.presentImportPanel()
                    }
                    .frame(width: 160)
                }
            }
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: 0x060C16).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(HUD.hairline, lineWidth: 0.8)
                )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x04070D).opacity(0.55))
    }
}
