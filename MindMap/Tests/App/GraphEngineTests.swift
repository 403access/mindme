import XCTest
import CoreGraphics
import MindMapCore

@MainActor
final class GraphEngineTests: XCTestCase {

    private func library() -> ThreadLibrary {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        return ThreadLibrary(threads: (0..<4).map { index in
            ConversationThread(
                id: "t\(index)",
                provider: index % 2 == 0 ? .chatgpt : .gemini,
                title: "Thread \(index)",
                createdAt: start,
                updatedAt: start.addingTimeInterval(TimeInterval(index)),
                messages: [
                    ChatMessage(
                        id: "m\(index)",
                        role: .user,
                        text: index % 2 == 0
                            ? "swiftui canvas rendering performance \(index)"
                            : "japanese kanji vocabulary practice \(index)"
                    )
                ]
            )
        })
    }

    private func makeEngine() -> GraphEngine {
        let engine = GraphEngine()
        engine.viewSize = CGSize(width: 800, height: 600)
        engine.setGraph(GraphBuilder.build(library: library(), filters: .default), refit: false)
        return engine
    }

    func testSetGraphPublishesPositionsAndEpoch() {
        let engine = makeEngine()
        XCTAssertEqual(engine.graph.stats.threadCount, 4)
        XCTAssertFalse(engine.frame.positions.isEmpty)
        XCTAssertFalse(engine.frame.positions3D.isEmpty)
        XCTAssertEqual(engine.frame.positions.count, engine.graph.nodes.count)
        XCTAssertEqual(engine.positionEpoch, 1)
        XCTAssertTrue(engine.autoFramed)
    }

    func testScreenAndWorldTransformsAreInverse() {
        let engine = makeEngine()
        let world = Vec2(25, -40)
        let screen = engine.screenPoint(for: world)
        XCTAssertEqual(screen.x, 425, accuracy: 0.001)
        XCTAssertEqual(screen.y, 260, accuracy: 0.001)
        XCTAssertEqual(engine.worldPoint(from: screen), world)

        engine.pan(byScreenTranslation: CGSize(width: 100, height: 50))
        XCTAssertEqual(engine.frame.camera.center, Vec2(-100, -50))
        XCTAssertEqual(engine.screenPoint(for: .zero), CGPoint(x: 500, y: 350))
    }

    func testZoomClampsAndKeepsTheAnchorFixed() {
        let engine = makeEngine()
        let center = CGPoint(x: 400, y: 300)
        engine.zoom(by: 2, around: center)
        XCTAssertEqual(engine.frame.camera.zoom, 2, accuracy: 0.0001)
        XCTAssertEqual(engine.frame.camera.center, .zero)

        engine.zoom(by: 100, around: center)
        XCTAssertEqual(engine.frame.camera.zoom, 2.8, accuracy: 0.0001)
        engine.zoom(by: 0.0001, around: center)
        XCTAssertEqual(engine.frame.camera.zoom, 0.16, accuracy: 0.0001)
    }

    func testHitTestingFindsTheRootAndRespectsRadii() throws {
        let engine = makeEngine()
        let center = CGPoint(x: 400, y: 300)
        let root = try XCTUnwrap(engine.hitTest(at: center))
        XCTAssertEqual(root.kind, .root)
        XCTAssertNil(engine.hitTest(at: CGPoint(x: 4, y: 4)))

        XCTAssertEqual(GraphEngine.hitRadius(for: MindMapNode(id: "r", kind: .root, label: "r")), 46)
        XCTAssertEqual(GraphEngine.hitRadius(for: MindMapNode(id: "g", kind: .group, label: "g")), 32)
        XCTAssertEqual(GraphEngine.hitRadius(for: MindMapNode(id: "t", kind: .thread, label: "t")), 8)
        XCTAssertEqual(GraphEngine.hitRadius(for: MindMapNode(id: "x", kind: .tag, label: "x")), 8)

        let empty = GraphEngine()
        XCTAssertNil(empty.hitTest(at: center))
    }

    func testMinimapBoundsIncludeEveryPosition() {
        let engine = makeEngine()
        let rect = engine.minimapWorldRect()
        XCTAssertLessThan(rect.min.x, rect.max.x)
        XCTAssertLessThan(rect.min.y, rect.max.y)
        for position in engine.frame.positions.values {
            XCTAssertGreaterThanOrEqual(position.x, rect.min.x)
            XCTAssertLessThanOrEqual(position.x, rect.max.x)
            XCTAssertGreaterThanOrEqual(position.y, rect.min.y)
            XCTAssertLessThanOrEqual(position.y, rect.max.y)
        }

        let fresh = GraphEngine()
        XCTAssertEqual(fresh.minimapWorldRect().min, Vec2(-1, -1))
        XCTAssertEqual(fresh.minimapWorldRect().max, Vec2(1, 1))
    }

    func testSpatialModeOrbitZoomPanAndReset() {
        let engine = makeEngine()
        XCTAssertFalse(engine.spatialMode)
        engine.setSpatialMode(true)
        XCTAssertTrue(engine.spatialMode)
        XCTAssertGreaterThan(engine.frame.camera3D.distance, 0)

        let initialYaw = engine.frame.camera3D.yaw
        engine.orbit(byScreenTranslation: CGSize(width: 10, height: -10))
        XCTAssertEqual(engine.frame.camera3D.yaw, initialYaw + 0.06, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(engine.frame.camera3D.pitch, 1.25)

        engine.orbit(byScreenTranslation: CGSize(width: 0, height: 10_000))
        XCTAssertEqual(engine.frame.camera3D.pitch, -1.25, accuracy: 0.0001)

        let beforeZoom = engine.frame.camera3D.distance
        engine.zoom(by: 2, around: .zero)
        XCTAssertEqual(engine.frame.camera3D.distance, max(280, beforeZoom / 2), accuracy: 0.0001)
        engine.zoom(by: 0.0001, around: .zero)
        XCTAssertEqual(engine.frame.camera3D.distance, 7_000, accuracy: 0.0001)

        let beforePan = engine.frame.camera3D.target
        engine.pan(byScreenTranslation: CGSize(width: 20, height: 10))
        XCTAssertNotEqual(engine.frame.camera3D.target, beforePan)

        engine.resetCamera()
        XCTAssertEqual(engine.frame.camera3D.yaw, -0.72, accuracy: 0.0001)
        XCTAssertEqual(engine.frame.camera3D.pitch, 0.30, accuracy: 0.0001)
        XCTAssertEqual(engine.frame.camera3D.distance, 1_600, accuracy: 0.0001)

        engine.setSpatialMode(false)
        XCTAssertFalse(engine.spatialMode)
    }

    func testProjectionMatchesTheCurrentFrame() {
        let engine = makeEngine()
        let projection = engine.projection
        XCTAssertEqual(projection.camera, engine.frame.camera)
        XCTAssertEqual(projection.size, engine.viewSize)
        XCTAssertEqual(projection.positions2D.count, engine.frame.positions.count)
        XCTAssertEqual(projection.modeBlend, engine.frame.modeBlend)
        XCTAssertNotNil(projection.project(nodeID: "root"))
    }

    func testFocusingAndCenteringDoNotCrashWithoutAView() {
        let engine = GraphEngine()
        engine.setGraph(GraphBuilder.build(library: library(), filters: .default), refit: false)
        engine.focus(nodeID: "root")
        engine.focus(nodeID: "missing")
        engine.center(world: Vec2(10, 20))
        engine.requestFit()
        engine.applyFit()
        engine.applySpatialFit()
        engine.resetCamera()
        XCTAssertNotNil(engine.frame)
    }
}
