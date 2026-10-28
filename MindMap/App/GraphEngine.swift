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
    var camera: Camera = .identity
    var time: Double = 0
    var isSettling: Bool = false
    var fps: Int = 60
}

/// Owns the render loop, force simulation, camera and hit testing. Publishes a
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
    private var timer: Timer?
    private var lastTick: Date?
    private var lastPublish: Date = .distantPast
    private var interactionDeadline: Date = .distantPast
    private var simulationSteps = 0
    private let maxSimulationSteps = 360
    private var autoFitStep: Int?

    private var targetCenter: Vec2 = .zero
    private var targetZoom: Double = 1
    private var hasFitted = false
    private var fitPending = false
    private var wasSettling = false
    private(set) var autoFramed = true

    private let minZoom = 0.16
    private let maxZoom = 2.8

    var hasFittedOnce: Bool { hasFitted }

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

        if refit || !hasFitted {
            hasFitted = true
            autoFramed = true
            autoFitStep = 46
            fitPending = true
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
            applyFit()
        } else if fitPending, viewSize.width > 10, viewSize.height > 10 {
            fitPending = false
            applyFit()
        }

        // Smooth camera toward the requested target.
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
        // The simulation steps at 60 Hz, but the canvas does not need to redraw
        // at full rate: 45 fps keeps the movement smooth at roughly half the cost.
        let activeInterval = 1.0 / 45.0
        let needsFrame = settling || cameraMoving || interacting || ambientActive
        let interval = (settling || cameraMoving || interacting) ? activeInterval : ambientInterval

        if needsFrame, now.timeIntervalSince(lastPublish) >= interval {
            publish(force: false)
        }
    }

    private func publish(force: Bool) {
        if !force, Date().timeIntervalSince(lastPublish) < 0.001 { return }
        frame = currentFrame
        lastPublish = Date()
    }

    // MARK: - Camera

    func requestFit() {
        interactionDeadline = Date().addingTimeInterval(0.8)
        fitPending = true
        if viewSize.width > 10 { applyFit() }
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

    func resetCamera() {
        interactionDeadline = Date().addingTimeInterval(0.8)
        autoFramed = false
        targetCenter = .zero
        targetZoom = 1
    }

    func focus(nodeID: String, zoom requestedZoom: Double? = nil) {
        guard let position = currentFrame.positions[nodeID] else { return }
        interactionDeadline = Date().addingTimeInterval(0.9)
        autoFramed = false
        targetCenter = position
        targetZoom = min(max(requestedZoom ?? max(currentFrame.camera.zoom, 0.95), minZoom), maxZoom)
    }

    func center(world point: Vec2) {
        interactionDeadline = Date().addingTimeInterval(0.9)
        targetCenter = point
    }

    func pan(byScreenTranslation translation: CGSize) {
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

    func zoom(by factor: Double, around point: CGPoint) {
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

    // MARK: - Hit testing

    func hitTest(at point: CGPoint) -> MindMapNode? {
        guard viewSize.width > 0 else { return nil }
        let camera = currentFrame.camera
        var best: (node: MindMapNode, distance: Double)?
        for node in graph.nodes {
            guard let position = currentFrame.positions[node.id] else { continue }
            let screenX = Double(viewSize.width) / 2 + (position.x - camera.center.x) * camera.zoom
            let screenY = Double(viewSize.height) / 2 + (position.y - camera.center.y) * camera.zoom
            let dx = Double(point.x) - screenX
            let dy = Double(point.y) - screenY
            let distance = (dx * dx + dy * dy).squareRoot()
            let radius = Self.hitRadius(for: node) + 6
            guard distance <= radius else { continue }
            if best == nil || distance < best!.distance {
                best = (node, distance)
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
