import SwiftUI
import CoreGraphics
import MindMapCore

/// Draws the constellation in screen space. Nodes and labels keep a stable
/// pixel size at every zoom level; camera zoom only changes their spacing.
///
/// A renderer lives for a single frame. Projections are resolved lazily into a
/// per-frame cache because edges, nodes, labels, and auras all revisit the same
/// node IDs.
final class MapRenderer {
    let graph: MindMapGraph
    let positions: [String: Vec2]
    let positions3D: [String: Vec3]
    let camera: Camera
    let camera3D: Camera3D
    let modeBlend: Double
    let size: CGSize
    let time: Double
    let selectedNodeID: String?
    let hoveredNodeID: String?
    let showLabels: Bool
    let showNodeNames: Bool
    let showSpend: Bool
    let motion: Bool
    let hybridWords: Bool
    let focusPath: Set<String>

    init(
        graph: MindMapGraph,
        positions: [String: Vec2],
        positions3D: [String: Vec3],
        camera: Camera,
        camera3D: Camera3D,
        modeBlend: Double,
        size: CGSize,
        time: Double,
        selectedNodeID: String?,
        hoveredNodeID: String?,
        showLabels: Bool,
        showNodeNames: Bool,
        showSpend: Bool,
        motion: Bool,
        hybridWords: Bool,
        focusPath: Set<String>
    ) {
        self.graph = graph
        self.positions = positions
        self.positions3D = positions3D
        self.camera = camera
        self.camera3D = camera3D
        self.modeBlend = modeBlend
        self.size = size
        self.time = time
        self.selectedNodeID = selectedNodeID
        self.hoveredNodeID = hoveredNodeID
        self.showLabels = showLabels
        self.showNodeNames = showNodeNames
        self.showSpend = showSpend
        self.motion = motion
        self.hybridWords = hybridWords
        self.focusPath = focusPath
    }

    private lazy var projection = MapProjection(
        camera: camera,
        camera3D: camera3D,
        modeBlend: modeBlend,
        size: size,
        positions2D: positions,
        positions3D: positions3D
    )

    /// One projection per node, computed on first use and shared by every pass.
    private lazy var projections: [String: ProjectedPoint] = {
        var result: [String: ProjectedPoint] = [:]
        result.reserveCapacity(graph.nodes.count)
        let projection = self.projection
        for node in graph.nodes {
            if let projected = projection.project(nodeID: node.id) {
                result[node.id] = projected
            }
        }
        return result
    }()

    private var spatialFade: Double { projection.spatialAlpha }

    private var halfWidth: CGFloat { size.width / 2 }
    private var halfHeight: CGFloat { size.height / 2 }

    private var spendActive: Bool { showSpend && graph.hasCostData }
    private var groupSpendCeiling: Double { graph.maxGroupCost }
    private var threadSpendCeiling: Double { graph.maxThreadCost }

    private func spendIntensity(_ cost: Double, ceiling: Double) -> Double {
        guard spendActive, cost > 0, ceiling > 0 else { return 0 }
        return sqrt(min(1, cost / ceiling))
    }

    private var focusID: String? { selectedNodeID ?? hoveredNodeID }
    private var focusSet: Set<String> { focusPath }

    // MARK: - Entry point

    func draw(into context: inout GraphicsContext) {
        drawGroupAuras(&context)
        if modeBlend < 0.99 {
            drawGrid(&context, fade: 1 - spatialFade)
            drawOrbits(&context, fade: 1 - spatialFade)
        }
        if modeBlend > 0.01 {
            drawSpatialFloor(&context)
            drawSpatialOrbits(&context)
        }
        drawEdges(&context)
        drawNodes(&context)
        drawLabels(&context)
    }

    /// Soft color fields behind each constellation.
    private func drawGroupAuras(_ context: inout GraphicsContext) {
        for group in graph.groupNodes {
            guard let center = displayPoint(group.id) else { continue }
            let children = graph.threadNodes.filter { $0.groupID == group.id }
            var maxDistance: CGFloat = 90
            for child in children {
                guard let childPoint = displayPoint(child.id) else { continue }
                maxDistance = max(maxDistance, hypot(childPoint.x - center.x, childPoint.y - center.y))
            }
            let radius = maxDistance + 70
            guard radius > 30 else { continue }
            let intensity = spendIntensity(group.cost, ceiling: groupSpendCeiling)
            let color = intensity > 0.015 ? HUD.spendColor(intensity) : HUD.color(for: group)
            let hotAlpha = 0.06 + 0.10 * intensity
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(hotAlpha), color.opacity(0.018), .clear]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }
    }

    // MARK: - Transform

    func screenPoint(_ world: Vec2) -> CGPoint {
        CGPoint(
            x: halfWidth + (world.x - camera.center.x) * camera.zoom,
            y: halfHeight + (world.y - camera.center.y) * camera.zoom
        )
    }

    private func screenPoint(for nodeID: String) -> CGPoint? {
        projections[nodeID]?.point
    }

    private func projection(for nodeID: String) -> ProjectedPoint? {
        projections[nodeID]
    }

    private func depthAlpha(_ projected: ProjectedPoint) -> Double {
        let brightness = min(1.0, max(0.40, 0.42 + projected.scale * 0.62))
        return 1 + (brightness - 1) * spatialFade
    }

    private func amplitude(_ nodeID: String) -> Double {
        guard motion else { return 0 }
        let hash = StableID.hash(nodeID)
        let phase = Double(hash % 6283) / 1000.0
        return sin(time * 0.55 + phase) * 1.6
    }

    private func displayPoint(_ nodeID: String) -> CGPoint? {
        guard let base = screenPoint(for: nodeID) else { return nil }
        let drift = amplitude(nodeID)
        return CGPoint(x: base.x, y: base.y + drift)
    }

    private func isHighlighted(_ id: String) -> Bool {
        focusID == nil || focusSet.contains(id)
    }

    private func isDimmed(_ id: String) -> Bool {
        focusID != nil && !focusSet.contains(id)
    }


    // MARK: - Grid & orbits

    private func drawGrid(_ context: inout GraphicsContext, fade: Double) {
        guard fade > 0.02, camera.zoom > 0.24 else { return }
        let topLeft = worldPoint(CGPoint(x: 0, y: 0))
        let bottomRight = worldPoint(CGPoint(x: size.width, y: size.height))
        let minor: Double = 140
        let major: Double = 700

        var minorPath = Path()
        var majorPath = Path()
        let startX = (topLeft.x / minor).rounded(.down) * minor
        let endX = (bottomRight.x / minor).rounded(.up) * minor
        let startY = (topLeft.y / minor).rounded(.down) * minor
        let endY = (bottomRight.y / minor).rounded(.up) * minor

        var x = startX
        while x <= endX {
            let isMajor = abs(x.truncatingRemainder(dividingBy: major)) < 0.001
            let top = screenPoint(Vec2(x, topLeft.y))
            let bottom = screenPoint(Vec2(x, bottomRight.y))
            var path = Path()
            path.move(to: top)
            path.addLine(to: bottom)
            if isMajor { majorPath.addPath(path) } else { minorPath.addPath(path) }
            x += minor
        }

        var y = startY
        while y <= endY {
            let isMajor = abs(y.truncatingRemainder(dividingBy: major)) < 0.001
            let left = screenPoint(Vec2(topLeft.x, y))
            let right = screenPoint(Vec2(bottomRight.x, y))
            var path = Path()
            path.move(to: left)
            path.addLine(to: right)
            if isMajor { majorPath.addPath(path) } else { minorPath.addPath(path) }
            y += minor
        }

        context.stroke(minorPath, with: .color(Color.white.opacity(0.022 * fade)), lineWidth: 0.5)
        context.stroke(majorPath, with: .color(HUD.accent.opacity(0.065 * fade)), lineWidth: 0.6)
    }

    private func drawOrbits(_ context: inout GraphicsContext, fade: Double) {
        guard fade > 0.02, let root = displayPoint("root") else { return }
        let clock = motion ? time : 0
        let radii: [Double] = [330, 660, 990]
        for (index, radius) in radii.enumerated() {
            let pixelRadius = CGFloat(radius * camera.zoom)
            guard pixelRadius > 30, pixelRadius < max(size.width, size.height) * 2.2 else { continue }
            let rect = CGRect(
                x: root.x - pixelRadius,
                y: root.y - pixelRadius,
                width: pixelRadius * 2,
                height: pixelRadius * 2
            )
            var path = Path()
            path.addEllipse(in: rect)
            context.stroke(
                path,
                with: .color(HUD.accent.opacity((index == 0 ? 0.075 : 0.035) * fade)),
                style: StrokeStyle(
                    lineWidth: 0.7,
                    dash: index == 0 ? [2, 9] : [1, 14],
                    dashPhase: clock * (index % 2 == 0 ? 5 : -4)
                )
            )

            if index == 0 {
                let tickPath = Path { path in
                    for tick in 0..<48 {
                        let angle = Double(tick) / 48 * 2 * .pi + clock * 0.02
                        let inner = Vec2(cos(angle), sin(angle)) * (radius - 7)
                        let outer = Vec2(cos(angle), sin(angle)) * (radius + 7)
                        path.move(to: screenPoint(inner))
                        path.addLine(to: screenPoint(outer))
                    }
                }
                context.stroke(tickPath, with: .color(HUD.accent.opacity(0.05 * fade)), lineWidth: 0.6)
            }
        }

        let sweepRadius = CGFloat(330 * camera.zoom)
        if sweepRadius > 40 {
            var sweep = Path()
            let start = clock * 0.28
            sweep.addArc(
                center: root,
                radius: sweepRadius,
                startAngle: .radians(start),
                endAngle: .radians(start + 0.65),
                clockwise: false
            )
            context.stroke(
                sweep,
                with: .linearGradient(
                    Gradient(colors: [HUD.accent.opacity(0.22 * fade), HUD.accent.opacity(0)]),
                    startPoint: CGPoint(x: root.x - sweepRadius, y: root.y),
                    endPoint: CGPoint(x: root.x + sweepRadius, y: root.y)
                ),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
        }
    }


    // MARK: - Spatial environment

    private func drawSpatialFloor(_ context: inout GraphicsContext) {
        guard spatialFade > 0.02 else { return }
        let floorY = -640.0
        let extent = 1_900.0
        let step = 190.0
        let fade = spatialFade

        var minor = Path()
        var major = Path()
        var index = 0
        var x = -extent
        while x <= extent {
            if let a = projection.project(world: Vec3(x, floorY, -extent)),
               let b = projection.project(world: Vec3(x, floorY, extent)) {
                var p = Path()
                p.move(to: a.point)
                p.addLine(to: b.point)
                if index % 5 == 0 { major.addPath(p) } else { minor.addPath(p) }
            }
            x += step
            index += 1
        }
        index = 0
        var z = -extent
        while z <= extent {
            if let a = projection.project(world: Vec3(-extent, floorY, z)),
               let b = projection.project(world: Vec3(extent, floorY, z)) {
                var p = Path()
                p.move(to: a.point)
                p.addLine(to: b.point)
                if index % 5 == 0 { major.addPath(p) } else { minor.addPath(p) }
            }
            z += step
            index += 1
        }

        context.stroke(minor, with: .color(HUD.accent.opacity(0.032 * fade)), lineWidth: 0.5)
        context.stroke(major, with: .color(HUD.accent.opacity(0.065 * fade)), lineWidth: 0.7)

        // Vertical tether from each group hub to the floor, anchoring clusters
        // in space and making the perspective legible.
        var stems = Path()
        for group in graph.groupNodes {
            guard let anchor = positions3D[group.id] else { continue }
            guard let top = projection.project(world: anchor),
                  let bottom = projection.project(world: Vec3(anchor.x, floorY, anchor.z))
            else { continue }
            stems.move(to: top.point)
            stems.addLine(to: bottom.point)
        }
        context.stroke(
            stems,
            with: .color(HUD.accent.opacity(0.09 * fade)),
            style: StrokeStyle(lineWidth: 0.7, dash: [2, 8])
        )

        // Floor ring under the root.
        var ring = Path()
        var started = false
        for segment in 0...96 {
            let angle = Double(segment) / 96 * 2 * .pi
            let point = Vec3(cos(angle) * 540, floorY, sin(angle) * 540)
            guard let projected = projection.project(world: point) else { continue }
            if !started {
                ring.move(to: projected.point)
                started = true
            } else {
                ring.addLine(to: projected.point)
            }
        }
        context.stroke(ring, with: .color(HUD.accent.opacity(0.075 * fade)), lineWidth: 0.8)
    }

    private func drawSpatialOrbits(_ context: inout GraphicsContext) {
        guard spatialFade > 0.02 else { return }
        let fade = spatialFade
        for (index, radius) in [360.0, 720.0, 1_080.0].enumerated() {
            var path = Path()
            var started = false
            for segment in 0...96 {
                let angle = Double(segment) / 96 * 2 * .pi
                let point = Vec3(cos(angle) * radius, 0, sin(angle) * radius)
                guard let projected = projection.project(world: point) else {
                    started = false
                    continue
                }
                if !started {
                    path.move(to: projected.point)
                    started = true
                } else {
                    path.addLine(to: projected.point)
                }
            }
            context.stroke(
                path,
                with: .color(HUD.accent.opacity((index == 0 ? 0.10 : 0.045) * fade)),
                style: StrokeStyle(
                    lineWidth: 0.7,
                    dash: index == 0 ? [2, 9] : [1, 14],
                    dashPhase: time * (index % 2 == 0 ? 4 : -3)
                )
            )
        }
    }

    // MARK: - Edges

    private func edgeTint(_ edge: MindMapEdge) -> Color {
        // Root and region edges point at the hub whose spend defines the tint;
        // group→thread edges inherit their group.
        let nodeID = (edge.kind == .rootGroup || edge.kind == .regionGroup)
            ? edge.target
            : edge.source
        if let node = graph.node(id: nodeID) {
            if spendActive, node.kind == .group {
                let intensity = spendIntensity(node.cost, ceiling: groupSpendCeiling)
                if intensity > 0.015 { return HUD.spendColor(intensity) }
            }
            return HUD.color(for: node)
        }
        return HUD.accent
    }

    private func drawEdges(_ context: inout GraphicsContext) {
        let focusActive = focusID != nil
        var pulseBudget = focusActive ? 90 : 14

        for (index, edge) in graph.edges.enumerated() {
            guard let from = displayPoint(edge.source), let to = displayPoint(edge.target),
                  let projectedFrom = projection(for: edge.source),
                  let projectedTo = projection(for: edge.target)
            else { continue }
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: -240, dy: -240)
            if !rect.contains(from) && !rect.contains(to) { continue }

            let averageScale = (projectedFrom.scale + projectedTo.scale) / 2
            let edgeScale = 1 + (min(1.7, max(0.5, averageScale)) - 1) * spatialFade
            let depthFade = 1 + (min(1, max(0.35, 0.35 + averageScale * 0.65)) - 1) * spatialFade
            let highlighted = isHighlighted(edge.source) && isHighlighted(edge.target)
            let dimmed = focusActive && !highlighted
            let tint = edgeTint(edge)
            let curve = edgeCurve(from: from, to: to, edge: edge)

            if !dimmed {
                let tagDamping = edge.kind == .threadTag ? 0.72 : 1.0
                let baseAlpha = (highlighted ? (focusActive ? 0.5 : 0.115) : 0.04) * tagDamping * depthFade
                // The glow layer is only worth its draw cost when a path is
                // actually being inspected.
                if focusActive {
                    let glowAlpha = (highlighted ? 0.12 : 0.02) * tagDamping * depthFade
                    context.stroke(
                        curve.path,
                        with: .color(tint.opacity(glowAlpha)),
                        style: StrokeStyle(lineWidth: (highlighted ? 5.5 : 2.5) * edgeScale, lineCap: .round)
                    )
                }
                context.stroke(
                    curve.path,
                    with: .color(tint.opacity(baseAlpha)),
                    style: StrokeStyle(
                        lineWidth: (highlighted ? 1.15 : 0.65) * edgeScale,
                        lineCap: .round,
                        dash: edge.kind == .threadTag ? [1.5, 4.5] : []
                    )
                )
            } else {
                context.stroke(
                    curve.path,
                    with: .color(Color.white.opacity(0.04 * depthFade)),
                    style: StrokeStyle(lineWidth: 0.6, lineCap: .round)
                )
            }

            // Energy pulses flowing along active paths.
            let wantsPulse = highlighted && (focusActive || edge.kind == .rootGroup || index % 7 == 0)
            if wantsPulse && pulseBudget > 0 && motion {
                pulseBudget -= 1
                let speed = edge.kind == .rootGroup ? 0.10 : 0.16
                let hash = StableID.hash(edge.id)
                let offset = Double(hash % 1000) / 1000
                let phase = (time * speed + offset).truncatingRemainder(dividingBy: 1.0)
                let point = quadraticPoint(curve.from, curve.control, curve.to, phase)
                let pulseRadius: CGFloat = (edge.kind == .threadTag ? 1.3 : 1.9) * edgeScale
                let color = edge.kind == .threadTag ? HUD.accent.opacity(0.7) : tint
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - pulseRadius * 3.0,
                        y: point.y - pulseRadius * 3.0,
                        width: pulseRadius * 6.0,
                        height: pulseRadius * 6.0
                    )),
                    with: .color(color.opacity(0.16))
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - pulseRadius,
                        y: point.y - pulseRadius,
                        width: pulseRadius * 2,
                        height: pulseRadius * 2
                    )),
                    with: .color(color.opacity(0.95))
                )
            }
        }
    }

    private struct Curve {
        var path: Path
        var from: CGPoint
        var control: CGPoint
        var to: CGPoint
    }

    private func edgeCurve(from: CGPoint, to: CGPoint, edge: MindMapEdge) -> Curve {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = max(1, sqrt(dx * dx + dy * dy))
        let hash = StableID.hash(edge.id)
        let direction: CGFloat = hash % 2 == 0 ? 1 : -1
        let bend: CGFloat
        switch edge.kind {
        case .rootGroup: bend = 0
        case .regionGroup: bend = direction * min(20, distance * 0.06)
        case .groupThread: bend = direction * min(26, distance * 0.08)
        case .threadTag: bend = direction * min(18, distance * 0.14)
        }
        let normal = CGPoint(x: -dy / distance, y: dx / distance)
        let control = CGPoint(
            x: (from.x + to.x) / 2 + normal.x * bend,
            y: (from.y + to.y) / 2 + normal.y * bend
        )
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)
        return Curve(path: path, from: from, control: control, to: to)
    }

    private func quadraticPoint(_ a: CGPoint, _ control: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let t = CGFloat(t)
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * a.x + 2 * mt * t * control.x + t * t * b.x,
            y: mt * mt * a.y + 2 * mt * t * control.y + t * t * b.y
        )
    }

    // MARK: - Nodes

    private func drawNodes(_ context: inout GraphicsContext) {
        if modeBlend > 0.01 {
            let ordered = graph.nodes
                .filter { !(hybridWords && $0.kind == .tag) }
                .compactMap { node -> (MindMapNode, ProjectedPoint)? in
                    guard let projected = projection(for: node.id) else { return nil }
                    return (node, projected)
                }
                .sorted { $0.1.depth > $1.1.depth }

            for (node, projected) in ordered {
                let point = CGPoint(
                    x: projected.point.x,
                    y: projected.point.y + amplitude(node.id)
                )
                drawNodeScaled(node, at: point, scale: CGFloat(projected.scale), alpha: depthAlpha(projected), context: &context)
            }
        } else {
            // Tags sit behind the conversations on the flat map.
            if !hybridWords {
                for node in graph.tagNodes {
                    guard let point = displayPoint(node.id) else { continue }
                    drawNodeScaled(node, at: point, scale: 1, alpha: 1, context: &context)
                }
            }
            for node in graph.groupNodes {
                guard let point = displayPoint(node.id) else { continue }
                drawNodeScaled(node, at: point, scale: 1, alpha: 1, context: &context)
            }
            for node in graph.threadNodes {
                guard let point = displayPoint(node.id) else { continue }
                drawNodeScaled(node, at: point, scale: 1, alpha: 1, context: &context)
            }
            if let root = graph.rootNode, let point = displayPoint(root.id) {
                drawNodeScaled(root, at: point, scale: 1, alpha: 1, context: &context)
            }
        }
    }

    private func drawNodeScaled(
        _ node: MindMapNode,
        at point: CGPoint,
        scale: CGFloat,
        alpha: Double,
        context: inout GraphicsContext
    ) {
        let savedTransform = context.transform
        let savedOpacity = context.opacity
        context.opacity = savedOpacity * alpha
        if abs(scale - 1) > 0.01 {
            context.translateBy(x: point.x, y: point.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -point.x, y: -point.y)
        }
        switch node.kind {
        case .tag: drawTag(node, at: point, context: &context)
        case .group: drawGroup(node, at: point, context: &context)
        case .thread: drawThread(node, at: point, context: &context)
        case .root: drawRoot(node, at: point, context: &context)
        }
        context.transform = savedTransform
        context.opacity = savedOpacity
    }

    private func drawTag(_ node: MindMapNode, at point: CGPoint, context: inout GraphicsContext) {
        let highlighted = isHighlighted(node.id)
        let dimmed = isDimmed(node.id)
        let selected = selectedNodeID == node.id
        let hovered = hoveredNodeID == node.id
        let color = HUD.color(for: node)
        let baseAlpha = dimmed ? 0.22 : (highlighted ? 0.9 : 0.4)
        let diamondSize = 2.4 + min(2.2, node.weight * 0.35)

        var diamond = Path()
        diamond.move(to: CGPoint(x: point.x, y: point.y - diamondSize))
        diamond.addLine(to: CGPoint(x: point.x + diamondSize, y: point.y))
        diamond.addLine(to: CGPoint(x: point.x, y: point.y + diamondSize))
        diamond.addLine(to: CGPoint(x: point.x - diamondSize, y: point.y))
        diamond.closeSubpath()

        if selected || hovered {
            let halo = diamondSize + 7
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)),
                with: .color(color.opacity(0.12))
            )
        }

        context.fill(diamond, with: .color(color.opacity(baseAlpha * 0.35)))
        context.stroke(diamond, with: .color(color.opacity(baseAlpha)), lineWidth: selected ? 1.4 : 0.8)

        if selected {
            let ring = diamondSize + 4.5
            var circle = Path()
            circle.addEllipse(in: CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2, height: ring * 2))
            context.stroke(
                circle,
                with: .color(HUD.accent.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 3], dashPhase: time * 8)
            )
        }
    }

    private func drawGroup(_ node: MindMapNode, at point: CGPoint, context: inout GraphicsContext) {
        let selected = selectedNodeID == node.id
        let hovered = hoveredNodeID == node.id
        let focused = isHighlighted(node.id)
        let dimmed = isDimmed(node.id)
        let intensity = spendIntensity(node.cost, ceiling: groupSpendCeiling)
        let spendMuted = spendActive && node.cost <= 0
        let presence = dimmed ? 0.36 : (spendMuted ? 0.62 : 1.0)
        let color = intensity > 0.015 ? HUD.spendColor(intensity) : HUD.color(for: node)
        let radius: CGFloat = 26

        // Halo
        let haloRadius = radius + (selected ? 22 : 14)
        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - haloRadius * 1.4,
                y: point.y - haloRadius * 1.4,
                width: haloRadius * 2.8,
                height: haloRadius * 2.8
            )),
            with: .color(color.opacity((selected ? 0.055 : 0.025) * presence))
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - haloRadius,
                y: point.y - haloRadius,
                width: haloRadius * 2,
                height: haloRadius * 2
            )),
            with: .color(color.opacity((selected ? 0.14 : 0.06) * presence))
        )

        // Rotating dashed ring
        let ringRadius = radius + 9
        let ringRect = CGRect(
            x: point.x - ringRadius,
            y: point.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        )
        var ring = Path()
        ring.addEllipse(in: ringRect)
        context.stroke(
            ring,
            with: .color(color.opacity(0.30 * presence)),
            style: StrokeStyle(lineWidth: 0.8, dash: [2, 7], dashPhase: time * (selected ? 14 : 6))
        )

        // Spend gauge: a filled arc proportional to this hub's share of the
        // most expensive region. Magnitude is legible without reading numbers.
        if intensity > 0.01 {
            var gauge = Path()
            gauge.addArc(
                center: point,
                radius: radius + 16,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + 360 * intensity),
                clockwise: false
            )
            context.stroke(
                gauge,
                with: .color(HUD.spendColor(intensity).opacity(0.9 * presence)),
                style: StrokeStyle(lineWidth: 2.1, lineCap: .round)
            )
        }

        // Hexagon body
        let hex = hexagonPath(center: point, radius: radius, rotation: .pi / 6)
        context.fill(hex, with: .color(color.opacity((selected ? 0.20 : 0.10) * presence)))
        context.stroke(
            hex,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.95 * presence), color.opacity(0.45 * presence)]),
                startPoint: CGPoint(x: point.x - radius, y: point.y - radius),
                endPoint: CGPoint(x: point.x + radius, y: point.y + radius)
            ),
            lineWidth: selected ? 1.6 : 1.1
        )

        // Inner hexagon detail
        let inner = hexagonPath(center: point, radius: radius * 0.62, rotation: .pi / 6)
        context.stroke(inner, with: .color(color.opacity(0.28 * presence)), lineWidth: 0.6)

        let monogram: String
        let monogramSize: CGFloat
        let monogramTracking: CGFloat
        if showNodeNames, node.provider == nil {
            monogram = hubName(for: node)
            monogramSize = hubNameSize(for: monogram)
            monogramTracking = 0.15
        } else {
            monogram = node.provider?.shortName ?? "TOPIC"
            monogramSize = node.provider == nil ? 7.2 : 8.3
            monogramTracking = 0.8
        }
        drawText(
            monogram,
            at: CGPoint(x: point.x, y: point.y),
            font: HUDFont.label(monogramSize),
            color: color.opacity((focused ? 1 : 0.75) * presence),
            anchor: .center,
            tracking: monogramTracking,
            context: &context
        )

        // Badge sits on the outward side. In spend mode it carries the region's
        // dollar total; otherwise it keeps the thread count.
        let count = node.subtitle?.split(separator: " ").first.map(String.init) ?? ""
        let showsCost = spendActive && node.cost > 0
        // Only the meaningful spenders get a floating dollar amount. The heat
        // ramp still encodes everything; badges would otherwise turn the map
        // into a wall of $0.02 labels.
        let spendBadgeFloor = max(0.01, groupSpendCeiling * 0.035)
        // In spend mode the badge is either a meaningful dollar amount or
        // absent; mixing thread counts into a heat map reads as noise.
        let badgeLabel: String
        if spendActive {
            badgeLabel = node.cost >= spendBadgeFloor ? Format.cost(node.cost) : ""
        } else {
            badgeLabel = count
        }
        if !badgeLabel.isEmpty {
            let rootPoint = displayPoint("root") ?? CGPoint(x: halfWidth, y: halfHeight)
            let outwardX = point.x - rootPoint.x
            let outwardY = point.y - rootPoint.y
            let outwardLength = max(1, sqrt(outwardX * outwardX + outwardY * outwardY))
            let badgeCenter = CGPoint(
                x: point.x + outwardX / outwardLength * (radius + 12),
                y: point.y + outwardY / outwardLength * (radius + 12)
            )
            let resolved = context.resolve(
                Text(badgeLabel)
                    .font(HUDFont.micro(6.8))
                    .foregroundColor((showsCost ? HUD.spendColor(intensity) : color).opacity(0.95 * presence))
                    .tracking(0)
            )
            let measured = resolved.measure(in: CGSize(width: 140, height: 20))
            let height: CGFloat = 14
            let width = max(14, measured.width + (showsCost ? 9 : 5))
            let badgeRect = CGRect(
                x: badgeCenter.x - width / 2,
                y: badgeCenter.y - height / 2,
                width: width,
                height: height
            )
            let badgePath = Path(roundedRect: badgeRect, cornerRadius: height / 2)
            context.fill(badgePath, with: .color(Color(hex: 0x060B13).opacity(0.95)))
            context.stroke(
                badgePath,
                with: .color((showsCost ? HUD.spendColor(intensity) : color).opacity(0.75 * presence)),
                lineWidth: 0.7
            )
            context.draw(resolved, at: badgeCenter, anchor: .center)
        }

        if selected || hovered {
            drawReticle(at: point, radius: radius + 15, color: color, context: &context)
        }
    }

    private func drawThread(_ node: MindMapNode, at point: CGPoint, context: inout GraphicsContext) {
        let intensity = spendIntensity(node.cost, ceiling: threadSpendCeiling)
        let color = intensity > 0.015 ? HUD.spendColor(intensity) : HUD.color(for: node)
        let selected = selectedNodeID == node.id
        let hovered = hoveredNodeID == node.id
        let highlighted = isHighlighted(node.id)
        let dimmed = isDimmed(node.id)
        let presence = dimmed ? 0.28 : 1.0
        let radius = threadRadius(node, selected: selected, hovered: hovered)
            + (intensity > 0.015 ? CGFloat(intensity * 1.7) : 0)

        if !dimmed {
            let glow = radius + (selected ? 12 : hovered ? 9 : 5)
            let outerGlow = glow * 1.5
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - outerGlow,
                    y: point.y - outerGlow,
                    width: outerGlow * 2,
                    height: outerGlow * 2
                )),
                with: .color(color.opacity(selected ? 0.055 : 0.028))
            )
            if focusID != nil {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - glow,
                        y: point.y - glow,
                        width: glow * 2,
                        height: glow * 2
                    )),
                    with: .color(color.opacity(selected ? 0.16 : 0.08))
                )
            }
        }

        let coreRect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(Path(ellipseIn: coreRect), with: .color(color.opacity((highlighted ? 0.92 : 0.6) * presence)))
        context.stroke(
            Path(ellipseIn: coreRect),
            with: .color(Color.white.opacity((selected ? 0.9 : 0.35) * presence)),
            lineWidth: 0.7
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - radius * 0.34,
                y: point.y - radius * 0.34,
                width: radius * 0.68,
                height: radius * 0.68
            )),
            with: .color(Color.white.opacity((selected ? 0.95 : 0.55) * presence))
        )

        if selected {
            let ring = radius + 7
            var circle = Path()
            circle.addEllipse(in: CGRect(
                x: point.x - ring,
                y: point.y - ring,
                width: ring * 2,
                height: ring * 2
            ))
            context.stroke(
                circle,
                with: .color(color.opacity(0.95)),
                style: StrokeStyle(lineWidth: 1.2, dash: [3, 3.5], dashPhase: time * 10)
            )
            var ticks = Path()
            for tick in 0..<4 {
                let angle = Double(tick) * .pi / 2 + time * 0.25
                let inner = CGPoint(
                    x: point.x + cos(angle) * (ring + 3),
                    y: point.y + sin(angle) * (ring + 3)
                )
                let outer = CGPoint(
                    x: point.x + cos(angle) * (ring + 8),
                    y: point.y + sin(angle) * (ring + 8)
                )
                ticks.move(to: inner)
                ticks.addLine(to: outer)
            }
            context.stroke(ticks, with: .color(color.opacity(0.8)), lineWidth: 1)
        } else if hovered {
            var circle = Path()
            let ring = radius + 5
            circle.addEllipse(in: CGRect(
                x: point.x - ring,
                y: point.y - ring,
                width: ring * 2,
                height: ring * 2
            ))
            context.stroke(circle, with: .color(color.opacity(0.65)), lineWidth: 0.8)
        }
    }

    private func threadRadius(_ node: MindMapNode, selected: Bool, hovered: Bool) -> CGFloat {
        let base = 2.9 + min(3.6, node.weight * 0.95)
        return base + (selected ? 2.2 : hovered ? 1.2 : 0)
    }

    private func drawRoot(_ node: MindMapNode, at point: CGPoint, context: inout GraphicsContext) {
        let color = HUD.accent
        let breathe = motion ? sin(time * 0.8) * 2.5 : 0
        let radius: CGFloat = 34

        // Layered aura
        for layer in 0..<3 {
            let layerRadius = CGFloat(76 + Double(layer) * 24) + breathe
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - layerRadius,
                    y: point.y - layerRadius,
                    width: layerRadius * 2,
                    height: layerRadius * 2
                )),
                with: .radialGradient(
                    Gradient(colors: [
                        color.opacity([0.10, 0.05, 0.025][layer]),
                        .clear
                    ]),
                    center: point,
                    startRadius: 0,
                    endRadius: layerRadius
                )
            )
        }

        // Rotating outer rings
        for (index, ringRadius) in [radius + 20, radius + 31].enumerated() {
            let rect = CGRect(
                x: point.x - ringRadius,
                y: point.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )
            var ring = Path()
            ring.addEllipse(in: rect)
            context.stroke(
                ring,
                with: .color(color.opacity(index == 0 ? 0.24 : 0.12)),
                style: StrokeStyle(
                    lineWidth: 0.8,
                    dash: index == 0 ? [2, 10] : [14, 20],
                    dashPhase: time * (index == 0 ? 12 : -6)
                )
            )
        }

        // Rotating arc segments
        var arcs = Path()
        for index in 0..<3 {
            let arcRadius = radius + 24
            let start = time * 0.35 + Double(index) * 2.1
            arcs.addArc(
                center: point,
                radius: arcRadius,
                startAngle: .radians(start),
                endAngle: .radians(start + 0.65),
                clockwise: false
            )
        }
        context.stroke(arcs, with: .color(color.opacity(0.55)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

        // Body
        let hex = hexagonPath(center: point, radius: radius, rotation: .pi / 6)
        context.fill(hex, with: .linearGradient(
            Gradient(colors: [Color(hex: 0x0B2230), Color(hex: 0x060D16)]),
            startPoint: CGPoint(x: point.x, y: point.y - radius),
            endPoint: CGPoint(x: point.x, y: point.y + radius)
        ))
        context.stroke(hex, with: .color(color.opacity(0.9)), lineWidth: 1.4)
        let innerHex = hexagonPath(center: point, radius: radius * 0.72, rotation: .pi / 6)
        context.stroke(innerHex, with: .color(color.opacity(0.35)), lineWidth: 0.7)

        // Neural glyph
        let centerDot = CGRect(x: point.x - 2.4, y: point.y - 2.4, width: 4.8, height: 4.8)
        context.fill(Path(ellipseIn: centerDot), with: .color(Color.white.opacity(0.95)))
        var spokes = Path()
        for index in 0..<6 {
            let angle = Double(index) / 6 * 2 * .pi + time * 0.12
            let inner = CGPoint(x: point.x + cos(angle) * 6, y: point.y + sin(angle) * 6)
            let outer = CGPoint(x: point.x + cos(angle) * 15, y: point.y + sin(angle) * 15)
            spokes.move(to: inner)
            spokes.addLine(to: outer)
            context.fill(
                Path(ellipseIn: CGRect(x: outer.x - 1.3, y: outer.y - 1.3, width: 2.6, height: 2.6)),
                with: .color(color.opacity(0.85))
            )
        }
        context.stroke(spokes, with: .color(color.opacity(0.45)), lineWidth: 0.7)
    }

    // MARK: - Labels

    private func drawLabels(_ context: inout GraphicsContext) {
        if showLabels {
            var occupied: [CGRect] = []
            let spatial = modeBlend > 0.01
            let zoom = camera.zoom

            struct Candidate {
                var node: MindMapNode
                var point: CGPoint
                var scale: CGFloat
                var alpha: Double
                var priority: Double
            }

            var candidates: [Candidate] = []
            let topThreadIDs = Set(
                graph.threadNodes
                    .sorted { $0.weight > $1.weight }
                    .prefix(6)
                    .map(\.id)
            )

            for node in graph.threadNodes {
                guard let projected = projection(for: node.id) else { continue }
                let selected = selectedNodeID == node.id
                let hovered = hoveredNodeID == node.id
                let focused = isHighlighted(node.id)
                let notable = topThreadIDs.contains(node.id)
                let shouldShow: Bool
                if hybridWords {
                    shouldShow = selected || hovered
                } else if spatial {
                    shouldShow = selected || hovered
                } else {
                    shouldShow =
                        selected || hovered ||
                        (zoom >= 0.98 && focused) ||
                        (zoom >= 1.35)
                }
                guard shouldShow else { continue }
                let point = CGPoint(
                    x: projected.point.x,
                    y: projected.point.y + amplitude(node.id)
                )
                let priority = selected ? 1000.0 : hovered ? 900.0 : (notable ? 44.0 : 10.0) + node.weight
                candidates.append(Candidate(
                    node: node,
                    point: point,
                    scale: CGFloat(projected.scale),
                    alpha: depthAlpha(projected),
                    priority: priority
                ))
            }

            if !hybridWords, spatial || zoom >= 1.05 || selectedNodeID != nil {
                for node in graph.tagNodes {
                    guard let projected = projection(for: node.id) else { continue }
                    let selected = selectedNodeID == node.id
                    guard selected || (!spatial && zoom >= 1.7 && node.weight >= 4) else { continue }
                    let point = CGPoint(
                        x: projected.point.x,
                        y: projected.point.y + amplitude(node.id)
                    )
                    candidates.append(Candidate(
                        node: node,
                        point: point,
                        scale: CGFloat(projected.scale),
                        alpha: depthAlpha(projected),
                        priority: selected ? 950 : 5
                    ))
                }
            }

            candidates.sort { $0.priority > $1.priority }

            for candidate in candidates {
                let node = candidate.node
                let selected = selectedNodeID == node.id
                let hovered = hoveredNodeID == node.id
                let dimmed = isDimmed(node.id)
                if dimmed { continue }
                let color = HUD.color(for: node)
                let isTag = node.kind == .tag
                let text = shorten(node.label, limit: isTag ? 22 : (zoom > 1.2 || spatial ? 38 : 30))
                let font = isTag ? HUDFont.micro(7.6) : HUDFont.micro(8.6)
                let alpha = candidate.alpha * (dimmed ? 0.25 : 1)
                let textColor: Color = selected || hovered
                    ? HUD.text
                    : (isTag ? HUD.textSoft.opacity(0.85 * alpha) : HUD.text.opacity(0.72 * alpha))

                let resolved = context.resolve(
                    Text(text)
                        .font(font)
                        .foregroundColor(textColor)
                        .tracking(isTag ? 0.4 : 0.15)
                )
                let measured = resolved.measure(in: CGSize(width: 300, height: 30))
                let offsetY: CGFloat = (isTag ? 9 : threadRadius(node, selected: false, hovered: false) + 8) * max(0.65, min(1.5, candidate.scale))
                let origin = CGPoint(
                    x: candidate.point.x - measured.width / 2 - 3,
                    y: candidate.point.y + offsetY
                )
                var rect = CGRect(origin: origin, size: CGSize(width: measured.width + 6, height: measured.height + 2))

                if rect.minX < 4 || rect.maxX > size.width - 4 { continue }
                if rect.minY < 4 || rect.maxY > size.height - 4 { continue }
                if occupied.contains(where: { $0.intersects(rect.insetBy(dx: -3, dy: -2)) }) { continue }
                occupied.append(rect)

                let bg = Path(roundedRect: rect.insetBy(dx: -4, dy: -1), cornerRadius: 4)
                context.fill(
                    bg,
                    with: .color(Color(hex: 0x050A12).opacity((selected || hovered ? 0.82 : 0.55) * alpha))
                )
                if selected || hovered {
                    context.stroke(bg, with: .color(color.opacity(0.35 * alpha)), lineWidth: 0.6)
                }
                rect = rect.insetBy(dx: -4, dy: -1)
                occupied[occupied.count - 1] = rect

                context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }

            // Hubs always keep their labels, drawn inward toward the root.
            for group in graph.groupNodes {
                guard let projected = projection(for: group.id) else { continue }
                let selected = selectedNodeID == group.id
                let hovered = hoveredNodeID == group.id
                // With NAMES on, the hub already carries its name inside the
                // hexagon. Only surface the larger plate for focus states,
                // otherwise every topic would read twice.
                if showNodeNames, !selected, !hovered { continue }
                let dimmed = isDimmed(group.id)
                let spend = spendIntensity(group.cost, ceiling: groupSpendCeiling)
                let color = spend > 0.015 ? HUD.spendColor(spend) : HUD.color(for: group)
                let alpha = depthAlpha(projected) * (dimmed ? 0.3 : 1)
                let label = shorten(group.label, limit: 22)
                let resolved = context.resolve(
                    Text(label)
                        .font(HUDFont.label(8.4))
                        .foregroundColor(
                            selected || hovered ? HUD.text : color.opacity(0.82 * alpha)
                        )
                        .tracking(1.1)
                )
                let measured = resolved.measure(in: CGSize(width: 220, height: 24))
                let rootPoint = displayPoint("root") ?? CGPoint(x: halfWidth, y: halfHeight)
                let point = CGPoint(
                    x: projected.point.x,
                    y: projected.point.y + amplitude(group.id)
                )
                let dx = rootPoint.x - point.x
                let dy = rootPoint.y - point.y
                let length = max(1, sqrt(dx * dx + dy * dy))
                let labelPoint = CGPoint(
                    x: point.x + dx / length * 47 * max(0.7, min(1.4, projected.scale)),
                    y: point.y + dy / length * 47 * max(0.7, min(1.4, projected.scale))
                )
                let rect = CGRect(
                    x: labelPoint.x - measured.width / 2 - 2,
                    y: labelPoint.y - measured.height / 2,
                    width: measured.width + 4,
                    height: measured.height
                )
                if occupied.contains(where: { $0.intersects(rect.insetBy(dx: -2, dy: -1)) }) { continue }
                occupied.append(rect)

                let plate = Path(roundedRect: rect.insetBy(dx: -5, dy: -2), cornerRadius: 4)
                context.fill(plate, with: .color(Color(hex: 0x050A12).opacity((dimmed ? 0.35 : 0.82) * alpha)))
                context.stroke(
                    plate,
                    with: .color(color.opacity((selected || hovered ? 0.55 : 0.2) * alpha)),
                    lineWidth: 0.6
                )
                context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }
        }

        drawRootCaption(&context)
    }

    private func drawRootCaption(_ context: inout GraphicsContext) {
        guard spatialFade < 0.86,
              let root = graph.rootNode,
              let projected = projection(for: root.id),
              let point = displayPoint(root.id)
        else { return }
        let alpha = depthAlpha(projected) * (1 - spatialFade)
        guard alpha > 0.06 else { return }
        let scale = CGFloat(max(0.75, min(1.5, projected.scale)))
        let title = context.resolve(
            Text("MINDME")
                .font(HUDFont.label(12.5))
                .foregroundColor(HUD.text.opacity(alpha))
                .tracking(4.2)
        )
        let subtitle = context.resolve(
            Text(root.subtitle ?? "CONVERSATION NEXUS")
                .font(HUDFont.micro(7.4))
                .foregroundColor(HUD.accent.opacity(0.66 * alpha))
                .tracking(1.6)
        )
        let titleSize = title.measure(in: CGSize(width: 320, height: 30))
        let subtitleSize = subtitle.measure(in: CGSize(width: 380, height: 24))
        let plateWidth = max(titleSize.width, subtitleSize.width) + 16
        let plateHeight = titleSize.height + subtitleSize.height + 10
        let plateRect = CGRect(
            x: point.x - plateWidth / 2,
            y: point.y + 34 * scale + 20 * scale,
            width: plateWidth,
            height: plateHeight
        )
        guard plateRect.minY < size.height, plateRect.maxY > 0 else { return }
        let plate = Path(roundedRect: plateRect, cornerRadius: 5)
        context.fill(plate, with: .color(Color(hex: 0x050A12).opacity(0.62 * alpha)))
        context.stroke(plate, with: .color(HUD.accent.opacity(0.12 * alpha)), lineWidth: 0.6)
        context.draw(
            title,
            at: CGPoint(x: plateRect.midX, y: plateRect.minY + 5 + titleSize.height / 2),
            anchor: .center
        )
        context.draw(
            subtitle,
            at: CGPoint(x: plateRect.midX, y: plateRect.maxY - 5 - subtitleSize.height / 2),
            anchor: .center
        )
    }

    /// The word drawn inside a hub. Provider hubs keep their three-letter
    /// source code; topic/region/era hubs show their actual name.
    private func hubName(for node: MindMapNode) -> String {
        if let provider = node.provider { return provider.shortName }
        return shorten(node.label.uppercased(), limit: 12)
    }

    /// Long sub-region names (Architecture, Operations) shrink to fit the
    /// hexagon instead of being clipped to a generic monogram.
    private func hubNameSize(for text: String) -> CGFloat {
        let count = max(4, text.count)
        return max(5.4, min(8.0, 8.0 * 7.0 / CGFloat(count)))
    }

    private func shorten(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Helpers

    private func drawText(
        _ string: String,
        at point: CGPoint,
        font: Font,
        color: Color,
        anchor: UnitPoint,
        tracking: CGFloat,
        context: inout GraphicsContext
    ) {
        let resolved = context.resolve(
            Text(string)
                .font(font)
                .foregroundColor(color)
                .tracking(tracking)
        )
        context.draw(resolved, at: point, anchor: anchor)
    }

    private func hexagonPath(center: CGPoint, radius: CGFloat, rotation: CGFloat) -> Path {
        var path = Path()
        for index in 0..<6 {
            let angle = rotation + CGFloat(index) / 6 * 2 * .pi
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func drawReticle(
        at point: CGPoint,
        radius: CGFloat,
        color: Color,
        context: inout GraphicsContext
    ) {
        let gap = radius + 5
        let length: CGFloat = 7
        var path = Path()
        for sx in [-1.0, 1.0] as [CGFloat] {
            for sy in [-1.0, 1.0] as [CGFloat] {
                let corner = CGPoint(x: point.x + sx * gap, y: point.y + sy * gap)
                path.move(to: CGPoint(x: corner.x - sx * length, y: corner.y))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x, y: corner.y - sy * length))
            }
        }
        context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 1)
    }

    private func worldPoint(_ point: CGPoint) -> Vec2 {
        Vec2(
            camera.center.x + (Double(point.x) - Double(halfWidth)) / camera.zoom,
            camera.center.y + (Double(point.y) - Double(halfHeight)) / camera.zoom
        )
    }
}
