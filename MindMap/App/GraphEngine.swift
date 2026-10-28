import Foundation
import CoreGraphics
import SwiftUI
import AppKit
import MindMapCore

struct Camera: Equatable, Sendable {
    var center: Vec2 = .zero
    var zoom: Double = 1

    static let identity = Camera()
}

struct RenderFrame: Equatable {
    var positions: [String: Vec2] = [:]
    var positions3D: [String: Vec3] = [:]
    var camera: Camera = .identity
    var camera3D = Camera3D()
    var modeBlend: Double = 0
    var time: Double = 0
    var isSettling: Bool = false
    var fps: Int = 60
}

/// Owns the render loop, force simulation, cameras and hit testing. Publishes a
/// single `RenderFrame` per update so SwiftUI only invalidates once per tick.
/// Rendering is throttled once the simulation settles, keeping an idle map
/// close to zero CPU.
@MainActor
final class GraphEngine: ObservableObject {

    @Published private(set) var frame = RenderFrame()

    private(set) var graph: MindMapGraph = .empty
    var viewSize: CGSize = .zero
    var ambientMotion: Bool = true

    private var currentFrame = RenderFrame()
    private var layout: ForceLayout?
    private var spatialAnchors: [String: Vec3] = [:]
    private var timer: Timer?
    private var lastTick: Date?
    private var lastPublish: Date = .distantPast
    private var interactionDeadline: Date = .distantPast
    private var simulationSteps = 0
    private let maxSimulationSteps = 360
    private var autoFitStep: Int?

    private var targetCenter: Vec2 = .zero
    private var targetZoom: Double = 1
    private var targetCamera3D = Camera3D()
    private var targetModeBlend: Double = 0
    private var hasSpatialCamera = false
    private var fitPending = false
    private var spatialFitPending = false
    private var wasSettling = false
    private(set) var autoFramed = true
    private(set) var spatialAutoFramed = true

    private let minZoom = 0.16
    private let maxZoom = 2.8
    private let minDistance: Double = 280
    private let maxDistance: Double = 7_000

    private(set) var spatialMode: Bool = false
    var hasFittedOnce: Bool { hasFitted }
    private var hasFitted = false

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTick = nil
    }

    // MARK: - Graph

    func setGraph(_ newGraph: MindMapGraph, refit: Bool) {
        graph = newGraph
        let anchors = GraphLayout.anchors(for: newGraph)
        var layout = ForceLayout(graph: newGraph, anchors: anchors, previousPositions: currentFrame.positions)
        layout.wake()
        self.layout = layout
        simulationSteps = 0
        currentFrame.positions = layout.positions
        currentFrame.isSettling = true
        autoFitStep = nil

        spatialAnchors = GraphLayout3D.anchors(for: newGraph)
        currentFrame.positions3D = spatialAnchors

        if refit || !hasFitted {
            hasFitted = true
            autoFramed = true
            autoFitStep = 46
            fitPending = true
            if spatialMode { spatialFitPending = true }
        } else if spatialMode, spatialAutoFramed {
            spatialFitPending = true
        }
        publish(force: true)
    }

    // MARK: - Dimension

    func setSpatialMode(_ enabled: Bool) {
        guard enabled != spatialMode else { return }
        spatialMode = enabled
        targetModeBlend = enabled ? 1 : 0
        interactionDeadline = Date().addingTimeInterval(1.0)
        if enabled {
            spatialAutoFramed = true
            spatialFitPending = true
            if viewSize.width > 10 { applySpatialFit() }
        } else {
            spatialFitPending = false
            if autoFramed {
                fitPending = true
                if viewSize.width > 10 { applyFit() }
            }
        }
        publish(force: true)
    }

    // MARK: - Tick

    private func tick() {
        let now = Date()
        let dt = min(0.05, max(1.0 / 240.0, now.timeIntervalSince(lastTick ?? now)))
        lastTick = now

        if var layout, simulationSteps < maxSimulationSteps {
            layout.step(dt: dt)
            self.layout = layout
            currentFrame.positions = layout.positions
            simulationSteps += 1
            if simulationSteps >= maxSimulationSteps {
                currentFrame.isSettling = false
            }
        }

        if let autoFitStep, simulationSteps >= autoFitStep {
            self.autoFitStep = nil
            fitPending = false
            spatialFitPending = false
            applyFit()
            if spatialMode, spatialAutoFramed { applySpatialFit() }
        } else if fitPending, viewSize.width > 10, viewSize.height > 10 {
            fitPending = false
            applyFit()
        }
        if spatialFitPending, viewSize.width > 10, viewSize.height > 10 {
            spatialFitPending = false
            applySpatialFit()
        }

        // 2D camera smoothing.
        var camera = currentFrame.camera
        let smooth = 1.0 - exp(-9.5 * dt)
        camera.center += (targetCenter - camera.center) * smooth
        let currentLog = log(max(camera.zoom, 0.0001))
        let targetLog = log(max(targetZoom, 0.0001))
        camera.zoom = exp(currentLog + (targetLog - currentLog) * smooth)
        if camera.center.distance(to: targetCenter) < 0.15 { camera.center = targetCenter }
        if abs(camera.zoom - targetZoom) < 0.001 { camera.zoom = targetZoom }
        let cameraMoving = camera != currentFrame.camera
        currentFrame.camera = camera

        // 3D camera smoothing.
        var camera3D = currentFrame.camera3D
        let smooth3D = 1.0 - exp(-8.5 * dt)
        camera3D.yaw += (targetCamera3D.yaw - camera3D.yaw) * smooth3D
        camera3D.pitch += (targetCamera3D.pitch - camera3D.pitch) * smooth3D
        camera3D.target += (targetCamera3D.target - camera3D.target) * smooth3D
        let logDistance = log(max(camera3D.distance, 1))
        let logTarget = log(max(targetCamera3D.distance, 1))
        camera3D.distance = exp(logDistance + (logTarget - logDistance) * smooth3D)
        if abs(camera3D.yaw - targetCamera3D.yaw) < 0.0005 { camera3D.yaw = targetCamera3D.yaw }
        if abs(camera3D.pitch - targetCamera3D.pitch) < 0.0005 { camera3D.pitch = targetCamera3D.pitch }
        if camera3D.target.distance(to: targetCamera3D.target) < 0.2 { camera3D.target = targetCamera3D.target }
        if abs(camera3D.distance - targetCamera3D.distance) < 0.5 { camera3D.distance = targetCamera3D.distance }
        let camera3DMoving = camera3D != currentFrame.camera3D
        currentFrame.camera3D = camera3D

        // Crossfade between the flat map and the spatial projection.
        var modeMoving = false
        let blendDelta = targetModeBlend - currentFrame.modeBlend
        if abs(blendDelta) > 0.0005 {
            currentFrame.modeBlend += blendDelta * (1 - exp(-7.0 * dt))
            if abs(targetModeBlend - currentFrame.modeBlend) < 0.002 {
                currentFrame.modeBlend = targetModeBlend
            }
            modeMoving = true
        }

        currentFrame.time += dt

        let instant = 1.0 / max(now.timeIntervalSince(lastPublish), 0.0001)
        let smoothed = Double(currentFrame.fps) * 0.9 + min(instant, 120) * 0.1
        currentFrame.fps = Int(smoothed.rounded())

        let settling = simulationSteps < maxSimulationSteps
        if settling != wasSettling {
            wasSettling = settling
            publish(force: true)
            return
        }

        let interacting = now < interactionDeadline
        let ambientActive = ambientMotion && NSApp.isActive
        let ambientInterval = ambientActive ? 1.0 / 10.0 : 1.0 / 2.0
        let activeInterval = 1.0 / 45.0
        let active = settling || cameraMoving || camera3DMoving || modeMoving || interacting
        let needsFrame = active || ambientActive
        let interval = active ? activeInterval : ambientInterval

        if needsFrame, now.timeIntervalSince(lastPublish) >= interval {
            publish(force: false)
        }
    }

    private func publish(force: Bool) {
        if !force, Date().timeIntervalSince(lastPublish) < 0.001 { return }
        frame = currentFrame
        lastPublish = Date()
    }

    // MARK: - Fit

    func requestFit() {
        interactionDeadline = Date().addingTimeInterval(0.8)
        if spatialMode {
            spatialAutoFramed = true
            spatialFitPending = true
            if viewSize.width > 10 { applySpatialFit() }
        } else {
            fitPending = true
            if viewSize.width > 10 { applyFit() }
        }
    }

    func applyFit() {
        let points = currentFrame.positions.values.filter { $0.length.isFinite }
        guard !points.isEmpty else {
            targetCenter = .zero
            targetZoom = 1
            return
        }
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        let width = max(1, maxX - minX)
        let height = max(1, maxY - minY)
        let padding = max(48, min(Double(min(viewSize.width, viewSize.height)) * 0.10, 92))
        let availableWidth = max(100, Double(viewSize.width) - padding * 2)
        let availableHeight = max(100, Double(viewSize.height) - padding * 2)
        let zoom = min(availableWidth / width, availableHeight / height)
        targetCenter = Vec2((minX + maxX) / 2, (minY + maxY) / 2)
        targetZoom = min(max(zoom, 0.22), 1.4)
        autoFramed = true
    }

    func applySpatialFit() {
        spatialFitPending = false
        guard !spatialAnchors.isEmpty else { return }
        let fitted = targetCamera3D.fit(
            points: Array(spatialAnchors.values),
            in: viewSize,
            keepAngles: hasSpatialCamera
        )
        if !hasSpatialCamera {
            currentFrame.camera3D = fitted
            hasSpatialCamera = true
        }
        targetCamera3D = fitted
        spatialAutoFramed = true
    }

    func resetCamera() {
        interactionDeadline = Date().addingTimeInterval(0.8)
        autoFramed = false
        targetCenter = .zero
        targetZoom = 1
        if spatialMode {
            spatialAutoFramed = false
            var reset = Camera3D()
            reset.target = .zero
            targetCamera3D = reset
            currentFrame.camera3D = reset
            publish(force: true)
        }
    }

    // MARK: - Focus

    func focus(nodeID: String, zoom requestedZoom: Double? = nil) {
        interactionDeadline = Date().addingTimeInterval(0.9)
        if spatialMode {
            guard let point = spatialAnchors[nodeID] else { return }
            spatialAutoFramed = false
            targetCamera3D.target = point
            targetCamera3D.distance = min(
                targetCamera3D.distance,
                max(minDistance, 1_250)
            )
            publish(force: true)
            return
        }
        guard let position = currentFrame.positions[nodeID] else { return }
        autoFramed = false
        targetCenter = position
        targetZoom = min(max(requestedZoom ?? max(currentFrame.camera.zoom, 0.95), minZoom), maxZoom)
    }

    func center(world point: Vec2) {
        interactionDeadline = Date().addingTimeInterval(0.9)
        targetCenter = point
    }

    // MARK: - Navigation

    func pan(byScreenTranslation translation: CGSize) {
        if spatialMode {
            panSpatial(by: translation)
            return
        }
        guard currentFrame.camera.zoom > 0 else { return }
        interactionDeadline = Date().addingTimeInterval(0.5)
        autoFramed = false
        let delta = Vec2(-Double(translation.width), -Double(translation.height)) / currentFrame.camera.zoom
        var camera = currentFrame.camera
        camera.center += delta
        currentFrame.camera = camera
        targetCenter = camera.center
        targetZoom = camera.zoom
        publish(force: true)
    }

    private func panSpatial(by translation: CGSize) {
        interactionDeadline = Date().addingTimeInterval(0.5)
        spatialAutoFramed = false
        let delta = currentFrame.camera3D.panDelta(screenTranslation: translation, size: viewSize)
        var camera = currentFrame.camera3D
        camera.target += delta
        currentFrame.camera3D = camera
        targetCamera3D.target = camera.target
        publish(force: true)
    }

    func orbit(byScreenTranslation translation: CGSize) {
        guard spatialMode else { return }
        interactionDeadline = Date().addingTimeInterval(0.5)
        spatialAutoFramed = false
        var camera = currentFrame.camera3D
        let sensitivity = 0.006
        camera.yaw += Double(translation.width) * sensitivity
        camera.pitch = min(1.25, max(-1.25, camera.pitch - Double(translation.height) * sensitivity))
        currentFrame.camera3D = camera
        targetCamera3D.yaw = camera.yaw
        targetCamera3D.pitch = camera.pitch
        targetCamera3D.target = camera.target
        targetCamera3D.distance = camera.distance
        publish(force: true)
    }

    func zoom(by factor: Double, around point: CGPoint) {
        if spatialMode {
            zoomSpatial(by: factor)
            return
        }
        var camera = currentFrame.camera
        let before = worldPoint(from: point)
        let newZoom = min(max(camera.zoom * factor, minZoom), maxZoom)
        guard newZoom != camera.zoom else { return }
        interactionDeadline = Date().addingTimeInterval(0.5)
        autoFramed = false
        let half = Vec2(Double(viewSize.width) / 2, Double(viewSize.height) / 2)
        let anchorDelta = Vec2(Double(point.x), Double(point.y)) - half
        camera.zoom = newZoom
        camera.center = before - anchorDelta / newZoom
        currentFrame.camera = camera
        targetCenter = camera.center
        targetZoom = newZoom
        publish(force: true)
    }

    private func zoomSpatial(by factor: Double) {
        interactionDeadline = Date().addingTimeInterval(0.5)
        spatialAutoFramed = false
        let newDistance = min(maxDistance, max(minDistance, currentFrame.camera3D.distance / factor))
        currentFrame.camera3D.distance = newDistance
        targetCamera3D.distance = newDistance
        publish(force: true)
    }

    func screenPoint(for world: Vec2) -> CGPoint {
        let camera = currentFrame.camera
        return CGPoint(
            x: Double(viewSize.width) / 2 + (world.x - camera.center.x) * camera.zoom,
            y: Double(viewSize.height) / 2 + (world.y - camera.center.y) * camera.zoom
        )
    }

    func worldPoint(from screen: CGPoint) -> Vec2 {
        let camera = currentFrame.camera
        return Vec2(
            camera.center.x + (Double(screen.x) - Double(viewSize.width) / 2) / camera.zoom,
            camera.center.y + (Double(screen.y) - Double(viewSize.height) / 2) / camera.zoom
        )
    }

    var projection: MapProjection {
        MapProjection(
            camera: currentFrame.camera,
            camera3D: currentFrame.camera3D,
            modeBlend: currentFrame.modeBlend,
            size: viewSize,
            positions2D: currentFrame.positions,
            positions3D: currentFrame.positions3D
        )
    }

    // MARK: - Hit testing

    func hitTest(at point: CGPoint) -> MindMapNode? {
        guard viewSize.width > 0 else { return nil }
        let projection = self.projection
        var best: (node: MindMapNode, distance: Double, depth: Double)?
        for node in graph.nodes {
            guard let projected = projection.project(nodeID: node.id) else { continue }
            let dx = Double(point.x) - projected.point.x
            let dy = Double(point.y) - projected.point.y
            let distance = (dx * dx + dy * dy).squareRoot()
            let depthScale = spatialMode ? min(1.7, max(0.65, projected.scale)) : 1
            let radius = Self.hitRadius(for: node) * depthScale + 6
            guard distance <= radius else { continue }
            let depth = projected.depth
            if best == nil
                || distance < best!.distance - 0.5
                || (abs(distance - best!.distance) <= 0.5 && depth < best!.depth) {
                best = (node, distance, depth)
            }
        }
        return best?.node
    }

    static func hitRadius(for node: MindMapNode) -> Double {
        switch node.kind {
        case .root: return 46
        case .group: return 32
        case .thread: return 8
        case .tag: return 8
        }
    }

    // MARK: - Minimap

    func minimapWorldRect(padding: Double = 80) -> (min: Vec2, max: Vec2) {
        let points = currentFrame.positions.values
        guard !points.isEmpty else { return (Vec2(-1, -1), Vec2(1, 1)) }
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        let width = max(1, maxX - minX)
        let height = max(1, maxY - minY)
        let pad = max(padding, max(width, height) * 0.08)
        return (Vec2(minX - pad, minY - pad), Vec2(maxX + pad, maxY + pad))
    }
}
