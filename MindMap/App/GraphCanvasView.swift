import SwiftUI
#if os(macOS)
import AppKit
#endif
import MindMapCore

struct GraphCanvasView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: GraphEngine

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var hoverLocation: CGPoint?
    @State private var dragOrigin: CGPoint?
    @State private var lastTranslation: CGSize = .zero
    @State private var didPan = false
    @State private var dragPans = true
    @State private var lastMagnification: CGFloat = 1
    @State private var cursorIsHand = false
    @State private var hybridCache = HybridLayoutCache()

    private let mapCornerRadius: CGFloat = 18

    private var isCompactLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Canvas(opaque: false, colorMode: .extendedLinear) { context, canvasSize in
                    let hybrid = model.viewMode == .hybrid
                    let baseFocusID = model.selectedNodeID ?? model.hoveredNodeID
                    let searchFocus = baseFocusID == nil && model.isSearchHighlightActive
                    let focusPath = searchFocus
                        ? model.searchHighlightNodeIDs
                        : model.graph.focusPath(for: baseFocusID)
                    let renderer = MapRenderer(
                        graph: model.graph,
                        positions: engine.frame.positions,
                        positions3D: engine.frame.positions3D,
                        camera: engine.frame.camera,
                        camera3D: engine.frame.camera3D,
                        modeBlend: engine.frame.modeBlend,
                        size: canvasSize,
                        time: engine.frame.time,
                        selectedNodeID: model.selectedNodeID,
                        hoveredNodeID: model.hoveredNodeID,
                        showLabels: model.showLabels,
                        showNodeNames: model.showNodeNames,
                        showSpend: model.showSpend,
                        motion: model.motionEnabled,
                        hybridWords: hybrid,
                        focusPath: focusPath,
                        searchMatchIDs: searchFocus ? model.searchMatchNodeIDs : [],
                        searchFocusActive: searchFocus
                    )
                    renderer.draw(into: &context)
                    if hybrid {
                        let layout = hybridCache.layout(
                            graph: model.graph,
                            graphRevision: model.graphRevision,
                            projection: engine.projection,
                            size: canvasSize,
                            positionEpoch: engine.positionEpoch
                        )
                        HybridWordRenderer(
                            layout: layout,
                            selectedNodeID: model.selectedNodeID,
                            hoveredNodeID: model.hoveredNodeID,
                            focusPath: focusPath,
                            searchHighlightIDs: searchFocus ? model.searchWordIDs : [],
                            searchFocusActive: searchFocus
                        ).draw(into: &context)
                    }
                }
                .contentShape(Rectangle())
                .gesture(panGesture(size: size))
                .simultaneousGesture(magnifyGesture(size: size))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverLocation = location
                        updateHover(at: location, size: size)
                    case .ended:
                        hoverLocation = nil
                        model.hoveredNodeID = nil
                        setCursor(hand: false)
                    }
                }

                RadialGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.32)],
                    center: .center,
                    startRadius: min(size.width, size.height) * 0.24,
                    endRadius: max(size.width, size.height) * 0.72
                )
                .allowsHitTesting(false)
                .blendMode(.multiply)

                if model.graph.isEmpty {
                    EmptyMapState(model: model)
                } else {
                    mapOverlays(size: size)
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
                engine.viewSize = size
                engine.ambientMotion = model.motionEnabled
                engine.start()
                if !engine.hasFittedOnce {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        engine.requestFit()
                    }
                }
            }
            .onChange(of: model.motionEnabled) { _, enabled in
                engine.ambientMotion = enabled
            }
            .onChange(of: size) { _, newSize in
                engine.viewSize = newSize
                guard !model.graph.isEmpty else { return }
                if engine.spatialMode {
                    if engine.spatialAutoFramed { engine.requestFit() }
                } else if engine.autoFramed {
                    engine.requestFit()
                }
            }
            .onDisappear {
                hoverLocation = nil
                setCursor(hand: false)
                engine.stop()
            }
        }
    }

    // MARK: - Overlays

    private var topologyTitle: String {
        if model.viewMode == .hybrid { return "HYBRID CLOUD" }
        if model.is3D { return "SPATIAL TOPOLOGY" }
        switch model.grouping {
        case .provider: return "SOURCE TOPOLOGY"
        case .topic: return "TOPIC CONSTELLATIONS"
        case .region: return "REGION CONSTELLATIONS"
        case .era: return "TEMPORAL SHELLS"
        }
    }

    private var legendHint: String {
        if model.is3D {
            #if os(iOS)
            return "DRAG ORBIT · PINCH ZOOM"
            #else
            return "DRAG ORBIT · ⇧DRAG PAN · PINCH ZOOM"
            #endif
        }
        #if os(iOS)
        return "TOUCH TO INSPECT · PINCH ZOOM"
        #else
        return "HOVER TO IDENTIFY"
        #endif
    }

    @ViewBuilder
    private func mapOverlays(size: CGSize) -> some View {
        // Top-left telemetry strip
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(HUD.lime)
                    .frame(width: 4.5, height: 4.5)
                    .shadow(color: HUD.lime.opacity(0.9), radius: 4)
                Text(topologyTitle)
                    .font(HUDFont.micro(8))
                    .tracking(1.4)
                    .foregroundStyle(HUD.textSoft)
                Text("·")
                    .foregroundStyle(HUD.dim)
                Text(model.viewMode == .hybrid
                     ? "\(Format.count(model.graph.tagNodes.count, "WORD", "WORDS")) / \(Format.count(model.graph.stats.threadCount, "THREAD", "THREADS"))"
                     : "\(Format.count(model.graph.stats.groupCount, "HUB", "HUBS")) / \(Format.count(model.graph.stats.threadCount, "THREAD", "THREADS"))")
                    .font(HUDFont.micro(8))
                    .tracking(0.8)
                    .foregroundStyle(HUD.muted)
            }
            if !model.searchText.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 7.5, weight: .bold))
                    Text(model.searchIsolation
                         ? "FILTER: \(model.searchText.uppercased())"
                         : "MATCH: \(model.searchText.uppercased())")
                        .font(HUDFont.micro(7.5))
                        .tracking(0.7)
                    Text("· \(model.searchHitCount)")
                        .font(HUDFont.micro(7.5))
                        .tracking(0.5)
                        .opacity(0.75)
                }
                .foregroundStyle(model.searchHitCount > 0 ? HUD.amber : HUD.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(HUD.amber.opacity(0.08))
                        .overlay(Capsule().strokeBorder(HUD.amber.opacity(0.3), lineWidth: 0.7))
                )
            }

            if model.showSpend {
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(HUD.spendColor(Double(index) / 4))
                                .frame(width: 3.5, height: 9)
                        }
                    }
                    if model.graph.hasCostData {
                        Text("SPEND \(Format.cost(model.graph.stats.totalCost))")
                        if let top = model.graph.groupNodes
                            .filter({ $0.cost > 0 })
                            .max(by: { $0.cost < $1.cost }) {
                            Text("· TOP \(top.label) \(Format.cost(top.cost))")
                                .foregroundStyle(HUD.amber)
                        }
                    } else {
                        Text("NO COST IN VIEW")
                            .foregroundStyle(HUD.dim)
                    }
                }
                .font(HUDFont.micro(7.5))
                .tracking(0.7)
                .foregroundStyle(HUD.textSoft)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.03))
                        .overlay(Capsule().strokeBorder(HUD.hairline, lineWidth: 0.7))
                )
            }

            if model.graph.stats.groupCount == 1, model.graph.stats.threadCount > 10 {
                Button {
                    model.grouping = .topic
                    model.engine.requestFit()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 7, weight: .bold))
                        Text("SINGLE SOURCE · TRY TOPIC LENS")
                            .font(HUDFont.micro(7.2))
                            .tracking(0.7)
                    }
                    .foregroundStyle(HUD.accent.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(HUD.accent.opacity(0.07))
                            .overlay(Capsule().strokeBorder(HUD.accent.opacity(0.25), lineWidth: 0.7))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        // Camera controls, top-right
        VStack(spacing: 7) {
            ViewModeControl(selection: $model.viewMode, compact: true)

            Button {
                model.toggle3D()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "cube")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(model.is3D ? "3D" : "2D")
                        .font(HUDFont.micro(7.5))
                        .tracking(0.4)
                }
                .foregroundStyle(model.is3D ? HUD.accent : HUD.textSoft)
                .frame(width: 42, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(model.is3D ? HUD.accent.opacity(0.12) : Color.white.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(model.is3D ? HUD.accent.opacity(0.45) : HUD.hairline, lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)
            .help("Toggle 3D perspective  ⌘3")

            Button {
                model.toggleSpend()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text("COST")
                        .font(HUDFont.micro(7))
                        .tracking(0.4)
                }
                .foregroundStyle(model.showSpend ? HUD.amber : HUD.textSoft)
                .frame(width: 46, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(model.showSpend ? HUD.amber.opacity(0.12) : Color.white.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(model.showSpend ? HUD.amber.opacity(0.45) : HUD.hairline, lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)
            .help("Toggle spend heat")

            if !isCompactLayout {
                HUDIconButton(systemName: "plus", help: "Zoom in") {
                    zoom(by: 1.22, at: CGPoint(x: size.width / 2, y: size.height / 2))
                }
                HUDIconButton(systemName: "minus", help: "Zoom out") {
                    zoom(by: 1 / 1.22, at: CGPoint(x: size.width / 2, y: size.height / 2))
                }
            }
            HUDIconButton(systemName: "scope", help: "Fit map  ⌘0") {
                engine.requestFit()
            }
            if !isCompactLayout {
                HUDIconButton(
                    systemName: "textformat",
                    help: "Toggle labels",
                    active: model.showLabels
                ) {
                    model.showLabels.toggle()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

        // Zoom readout
        if !isCompactLayout {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 7) {
                        if model.is3D {
                            Text("3D")
                                .font(HUDFont.micro(8.5))
                                .tracking(0.8)
                                .foregroundStyle(HUD.accent.opacity(0.9))
                            Rectangle().fill(HUD.hairline).frame(width: 1, height: 10)
                            Text("DIST \(Int(engine.frame.camera3D.distance))")
                                .font(HUDFont.micro(8))
                                .tracking(0.4)
                                .foregroundStyle(HUD.textSoft)
                            Rectangle().fill(HUD.hairline).frame(width: 1, height: 10)
                            Text("\(Int(engine.frame.camera3D.yaw * 180 / .pi))° / \(Int(engine.frame.camera3D.pitch * 180 / .pi))°")
                                .font(HUDFont.micro(8))
                                .tracking(0.4)
                                .foregroundStyle(HUD.muted)
                        } else {
                            Text("\(Int((engine.frame.camera.zoom * 100).rounded()))%")
                                .font(HUDFont.micro(8.5))
                                .tracking(0.6)
                                .foregroundStyle(HUD.textSoft)
                        }
                        Rectangle().fill(HUD.hairline).frame(width: 1, height: 10)
                        Text(engine.frame.isSettling ? "\(engine.frame.fps) FPS" : "ECO")
                            .font(HUDFont.micro(8))
                            .tracking(0.5)
                            .foregroundStyle(engine.frame.isSettling ? HUD.muted : HUD.lime.opacity(0.7))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: 0x050A12).opacity(0.8)))
                    .overlay(Capsule().strokeBorder(HUD.hairline, lineWidth: 0.7))
                    .padding(.trailing, 176)
                    .padding(.bottom, 14)
                }
            }
        }

        // Minimap (2D) or orbit gizmo (3D)
        if !isCompactLayout {
            Group {
                if model.is3D {
                    SpatialGizmo(engine: engine)
                } else {
                    MinimapView(model: model, engine: engine)
                }
            }
            .frame(width: 154, height: 104)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }

        // Legend, bottom-left
        HStack(spacing: 12) {
            Text(legendHint)
                .font(HUDFont.micro(7))
                .tracking(0.9)
                .foregroundStyle(model.is3D ? HUD.accent.opacity(0.7) : HUD.dim.opacity(0.7))
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
            if model.showTags && model.graph.stats.tagCount > 0 {
                HStack(spacing: 4) {
                    Diamond().fill(HUD.accent.opacity(0.65)).frame(width: 5, height: 5)
                    Text("TAG")
                        .font(HUDFont.micro(7.5))
                        .tracking(0.8)
                        .foregroundStyle(HUD.muted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

        // Hover card
        if let location = hoverLocation,
           let nodeID = model.hoveredNodeID,
           let node = model.graph.node(id: nodeID) {
            HoverCard(node: node, model: model, engine: engine)
                .fixedSize()
                .position(
                    x: min(max(location.x + 18, 130), size.width - 130),
                    y: min(max(location.y + 20, 60), size.height - 90)
                )
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: - Gestures

    private func panGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = value.startLocation
                    lastTranslation = .zero
                    didPan = false
                    #if os(macOS)
                    dragPans = !engine.spatialMode || NSEvent.modifierFlags.contains(.shift)
                    #else
                    // Touch has no shift modifier; 3D drags orbit. Two-finger
                    // pinch still zooms and the fit control reframes the scene.
                    dragPans = !engine.spatialMode
                    #endif
                }
                let total = hypot(value.translation.width, value.translation.height)
                if total > 3 { didPan = true }
                guard didPan else { return }
                let delta = CGSize(
                    width: value.translation.width - lastTranslation.width,
                    height: value.translation.height - lastTranslation.height
                )
                if engine.spatialMode, !dragPans {
                    engine.orbit(byScreenTranslation: delta)
                } else {
                    engine.pan(byScreenTranslation: delta)
                }
                lastTranslation = value.translation
            }
            .onEnded { value in
                defer {
                    dragOrigin = nil
                    lastTranslation = .zero
                    didPan = false
                }
                guard let origin = dragOrigin else { return }
                let total = hypot(value.translation.width, value.translation.height)
                if total <= 4 {
                    let point = origin
                    if model.viewMode == .hybrid,
                       let word = hybridLayout(size: size).word(at: point) {
                        model.select(word.id)
                    } else if let node = engine.hitTest(at: point) {
                        model.select(node.id)
                    } else {
                        model.deselect()
                    }
                }
            }
    }

    private func magnifyGesture(size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.005)
            .onChanged { value in
                let delta = value.magnification / lastMagnification
                lastMagnification = value.magnification
                let anchor = CGPoint(
                    x: value.startAnchor.x * size.width,
                    y: value.startAnchor.y * size.height
                )
                engine.zoom(by: Double(delta), around: anchor)
            }
            .onEnded { _ in
                lastMagnification = 1
            }
    }

    private func zoom(by factor: Double, at point: CGPoint) {
        engine.zoom(by: factor, around: point)
    }

    private func updateHover(at location: CGPoint, size: CGSize) {
        if model.viewMode == .hybrid,
           let word = hybridLayout(size: size).word(at: location) {
            if model.hoveredNodeID != word.id {
                model.hoveredNodeID = word.id
            }
            setCursor(hand: true)
            return
        }
        let node = engine.hitTest(at: location)
        if model.hoveredNodeID != node?.id {
            model.hoveredNodeID = node?.id
        }
        setCursor(hand: node != nil)
    }

    private func hybridLayout(size: CGSize) -> HybridWordLayout {
        guard model.viewMode == .hybrid, !model.graph.isEmpty else { return .empty }
        return hybridCache.layout(
            graph: model.graph,
            graphRevision: model.graphRevision,
            projection: engine.projection,
            size: size,
            positionEpoch: engine.positionEpoch
        )
    }

    private func setCursor(hand: Bool) {
        guard hand != cursorIsHand else { return }
        cursorIsHand = hand
        Platform.setPointer(hand: hand)
    }
}

// MARK: - Static backdrop

struct MapBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x04060C), Color(hex: 0x060B16), Color(hex: 0x04060B)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [HUD.accent.opacity(0.075), HUD.accent.opacity(0.015), .clear],
                center: .init(x: 0.55, y: 0.48),
                startRadius: 0,
                endRadius: 700
            )

            RadialGradient(
                colors: [HUD.magenta.opacity(0.05), .clear],
                center: .init(x: 0.9, y: 0.1),
                startRadius: 0,
                endRadius: 480
            )

            RadialGradient(
                colors: [Color(hex: 0x3E6BFF).opacity(0.05), .clear],
                center: .init(x: 0.08, y: 0.95),
                startRadius: 0,
                endRadius: 520
            )

            Canvas { context, size in
                for index in 0..<92 {
                    let hash = StableID.hash("map-star-\(index)")
                    let x = CGFloat(hash % 10_000) / 10_000 * size.width
                    let y = CGFloat((hash >> 16) % 10_000) / 10_000 * size.height
                    let alpha = 0.12 + Double((hash >> 24) % 100) / 100 * 0.24
                    let radius = 0.45 + CGFloat((hash >> 40) % 100) / 100 * 0.8
                    let color = index % 11 == 0 ? HUD.accent : (index % 17 == 0 ? HUD.magenta : Color.white)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(color.opacity(alpha))
                    )
                }
                for index in 0..<4 {
                    let hash = StableID.hash("map-spark-\(index)")
                    let x = CGFloat(hash % 10_000) / 10_000 * size.width
                    let y = CGFloat((hash >> 16) % 10_000) / 10_000 * size.height
                    var path = Path()
                    path.move(to: CGPoint(x: x - 3, y: y))
                    path.addLine(to: CGPoint(x: x + 3, y: y))
                    path.move(to: CGPoint(x: x, y: y - 3))
                    path.addLine(to: CGPoint(x: x, y: y + 3))
                    context.stroke(path, with: .color(Color.white.opacity(0.12)), lineWidth: 0.5)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Hover card

struct HoverCard: View {
    var node: MindMapNode
    var model: AppModel
    var engine: GraphEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let provider = node.provider {
                    ProviderBadge(provider: provider, compact: true)
                } else {
                    MicroLabel(text: node.kind == .tag ? "SHARED TAG" : "CONSTELLATION", color: HUD.accent)
                }
                Spacer(minLength: 0)
                if let tag = node.tag {
                    Text("#\(tag)")
                        .font(HUDFont.micro(7.5))
                        .foregroundStyle(HUD.textSoft)
                }
            }
            Text(node.label)
                .font(HUDFont.display(12.5, weight: .medium))
                .foregroundStyle(HUD.text)
                .lineLimit(2)
                .frame(maxWidth: 210, alignment: .leading)
            HStack(spacing: 8) {
                if let subtitle = node.subtitle {
                    Text(subtitle.uppercased())
                        .font(HUDFont.micro(7.5))
                        .tracking(0.7)
                        .foregroundStyle(HUD.muted)
                }
                if node.kind == .thread {
                    Text("CLICK TO INSPECT")
                        .font(HUDFont.micro(7))
                        .tracking(0.6)
                        .foregroundStyle(HUD.accent.opacity(0.8))
                } else if node.kind == .tag {
                    Text("CLICK TO ISOLATE")
                        .font(HUDFont.micro(7))
                        .tracking(0.6)
                        .foregroundStyle(HUD.accent.opacity(0.8))
                }
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

// MARK: - Minimap

struct MinimapView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: GraphEngine

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rect = engine.minimapWorldRect()
            let spanX = max(1, rect.max.x - rect.min.x)
            let spanY = max(1, rect.max.y - rect.min.y)
            let scale = min((size.width - 16) / spanX, (size.height - 16) / spanY)
            let originX = 8 + ((size.width - 16) - spanX * scale) / 2
            let originY = 8 + ((size.height - 16) - spanY * scale) / 2

            let mapPoint: (Vec2) -> CGPoint = { world in
                CGPoint(
                    x: originX + (world.x - rect.min.x) * scale,
                    y: originY + (world.y - rect.min.y) * scale
                )
            }

            Canvas { context, _ in
                context.fill(
                    Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10),
                    with: .color(Color(hex: 0x050A12).opacity(0.86))
                )
                context.stroke(
                    Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10),
                    with: .color(HUD.accent.opacity(0.22)),
                    lineWidth: 0.8
                )

                for node in model.graph.nodes {
                    guard let position = engine.frame.positions[node.id] else { continue }
                    let point = mapPoint(position)
                    let radius: CGFloat = node.kind == .root ? 2.6 : (node.kind == .group ? 1.8 : 0.8)
                    var circle = Path()
                    circle.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                    context.fill(circle, with: .color(HUD.color(for: node).opacity(node.kind == .tag ? 0.35 : 0.8)))
                }

                // Viewport rectangle
                let camera = engine.frame.camera
                let halfWorldW = Double(engine.viewSize.width) / 2 / camera.zoom
                let halfWorldH = Double(engine.viewSize.height) / 2 / camera.zoom
                let topLeft = mapPoint(Vec2(camera.center.x - halfWorldW, camera.center.y - halfWorldH))
                let bottomRight = mapPoint(Vec2(camera.center.x + halfWorldW, camera.center.y + halfWorldH))
                let viewport = CGRect(
                    x: topLeft.x,
                    y: topLeft.y,
                    width: max(4, bottomRight.x - topLeft.x),
                    height: max(4, bottomRight.y - topLeft.y)
                ).intersection(CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
                if !viewport.isNull {
                    context.stroke(
                        Path(viewport),
                        with: .color(HUD.accent.opacity(0.65)),
                        lineWidth: 0.8
                    )
                }

                let scanY = 8 + (Double(engine.frame.time.truncatingRemainder(dividingBy: 4)) / 4) * (size.height - 16)
                var scan = Path()
                scan.move(to: CGPoint(x: 6, y: scanY))
                scan.addLine(to: CGPoint(x: size.width - 6, y: scanY))
                context.stroke(scan, with: .color(HUD.accent.opacity(0.06)), lineWidth: 0.6)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let world = Vec2(
                            rect.min.x + Double(value.location.x - originX) / scale,
                            rect.min.y + Double(value.location.y - originY) / scale
                        )
                        engine.center(world: world)
                    }
            )
        }
    }
}

// MARK: - Spatial gizmo

struct SpatialGizmo: View {
    @ObservedObject var engine: GraphEngine

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, _ in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 10),
                    with: .color(Color(hex: 0x050A12).opacity(0.88))
                )
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10),
                    with: .color(HUD.accent.opacity(0.25)),
                    lineWidth: 0.8
                )

                let camera = engine.frame.camera3D
                let center = CGPoint(x: size.width / 2, y: size.height / 2 - 5)
                let axisLength: CGFloat = 26

                func drawAxis(_ direction: Vec3, color: Color, label: String) {
                    let x = direction.dot(camera.right)
                    let y = -direction.dot(camera.up)
                    let length = max(0.001, hypot(x, y))
                    let end = CGPoint(
                        x: center.x + x / length * axisLength,
                        y: center.y + y / length * axisLength
                    )
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: end)
                    context.stroke(path, with: .color(color.opacity(0.75)), lineWidth: 1.2)
                    context.fill(
                        Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)),
                        with: .color(color)
                    )
                    let text = context.resolve(
                        Text(label)
                            .font(HUDFont.micro(6.5))
                            .foregroundColor(color.opacity(0.9))
                    )
                    context.draw(text, at: CGPoint(x: end.x + 6, y: end.y - 5), anchor: .leading)
                }

                drawAxis(Vec3(1, 0, 0), color: HUD.magenta, label: "X")
                drawAxis(Vec3(0, 1, 0), color: HUD.lime, label: "Y")
                drawAxis(Vec3(0, 0, 1), color: HUD.accent, label: "Z")

                let yaw = Int(camera.yaw * 180 / Double.pi)
                let pitch = Int(camera.pitch * 180 / Double.pi)
                let title = context.resolve(
                    Text("ORBIT")
                        .font(HUDFont.micro(7.5))
                        .foregroundColor(HUD.textSoft)
                        .tracking(1.2)
                )
                context.draw(title, at: CGPoint(x: 10, y: 11), anchor: .leading)
                let angles = context.resolve(
                    Text("YAW \(yaw)°  PITCH \(pitch)°")
                        .font(HUDFont.micro(6.4))
                        .foregroundColor(HUD.muted)
                        .tracking(0.4)
                )
                context.draw(angles, at: CGPoint(x: 10, y: size.height - 13), anchor: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                engine.requestFit()
            }
        }
        .help("3D orientation. Click to refit.")
    }
}

// MARK: - Empty state

struct EmptyMapState: View {
    var model: AppModel
    @State private var rotation: Double = 0

    private var hasLibrary: Bool { model.hasThreads }

    private var headline: String {
        guard hasLibrary else { return "NO SIGNAL" }
        if model.providers.isEmpty { return "NO SOURCES ACTIVE" }
        if !model.searchText.isEmpty { return "NO MATCHES" }
        return "NOTHING IN THIS WINDOW"
    }

    private var explanation: String {
        guard hasLibrary else {
            return "Import a conversation export to grow the constellation.\nEverything stays on this device."
        }
        if model.providers.isEmpty {
            return "Every source is switched off. Turn at least one back on\nin the filter matrix to restore the map."
        }
        if !model.searchText.isEmpty {
            return "No thread matches “\(model.searchText)”.\nClear the query or widen the time window."
        }
        return "No conversations were active in this time window.\nSwitch the window back to ALL to see the archive."
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .strokeBorder(HUD.accent.opacity(0.18 - Double(index) * 0.045), lineWidth: 0.8)
                        .frame(width: CGFloat(92 + index * 34), height: CGFloat(92 + index * 34))
                }
                Circle()
                    .trim(from: 0, to: 0.18)
                    .stroke(HUD.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(rotation))
                Image(systemName: hasLibrary ? "line.3.horizontal.decrease.circle" : "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 26, weight: .thin))
                    .foregroundStyle(HUD.accent.opacity(0.8))
            }
            .onAppear {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
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
                if hasLibrary {
                    HUDPrimaryButton(title: "Reset filters", icon: "arrow.counterclockwise") {
                        model.resetFilters()
                        model.engine.requestFit()
                    }
                    .frame(width: 154)
                    HUDGhostButton(title: "Import more", icon: "square.and.arrow.down") {
                        model.presentImportPanel()
                    }
                } else {
                    HUDPrimaryButton(title: "Import exports", icon: "square.and.arrow.down") {
                        model.presentImportPanel()
                    }
                    .frame(width: 160)
                    HUDGhostButton(title: "Load demo", icon: "sparkles") {
                        model.loadDemoData()
                    }
                }
            }

            if !hasLibrary {
                HStack(spacing: 14) {
                    formatHint("CHATGPT", "conversations.json")
                    formatHint("GEMINI", "My Activity.json")
                    formatHint("CLAUDE", "conversations.json")
                }
                .padding(.top, 2)
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

    private func formatHint(_ name: String, _ file: String) -> some View {
        VStack(spacing: 3) {
            Text(name)
                .font(HUDFont.micro(7.5))
                .tracking(1)
                .foregroundStyle(HUD.accent.opacity(0.7))
            Text(file)
                .font(HUDFont.micro(7))
                .foregroundStyle(HUD.dim)
        }
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
