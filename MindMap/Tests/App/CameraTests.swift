import XCTest
import CoreGraphics
import MindMapCore

final class Camera3DTests: XCTestCase {

    func testCameraBasisIsOrthonormal() {
        let camera = Camera3D()
        XCTAssertEqual(camera.position.length, 1_600, accuracy: 0.001)
        XCTAssertEqual(camera.forward.length, 1, accuracy: 0.0001)
        XCTAssertEqual(camera.right.length, 1, accuracy: 0.0001)
        XCTAssertEqual(camera.up.length, 1, accuracy: 0.0001)
        XCTAssertEqual(camera.forward.dot(camera.right), 0, accuracy: 0.0001)
        XCTAssertEqual(camera.forward.dot(camera.up), 0, accuracy: 0.0001)
        XCTAssertEqual(camera.right.dot(camera.up), 0, accuracy: 0.0001)
    }

    func testProjectionOfTargetIsCentered() throws {
        let camera = Camera3D()
        let size = CGSize(width: 1_000, height: 600)
        let projected = try XCTUnwrap(camera.project(camera.target, in: size))
        XCTAssertEqual(projected.point.x, 500, accuracy: 0.001)
        XCTAssertEqual(projected.point.y, 300, accuracy: 0.001)
        XCTAssertEqual(projected.depth, camera.distance, accuracy: 0.001)
        XCTAssertEqual(projected.scale, 1, accuracy: 0.001)
    }

    func testProjectionRejectsTinyCanvasAndPointsBehindCamera() {
        let camera = Camera3D()
        XCTAssertNil(camera.project(.zero, in: CGSize(width: 1, height: 1)))
        XCTAssertNil(camera.project(.zero, in: CGSize(width: 0, height: 0)))
        let behind = camera.position - camera.forward * 10
        XCTAssertNil(camera.project(behind, in: CGSize(width: 800, height: 600)))
    }

    func testFitFramesPointsAndHonoursAngles() {
        let points: [Vec3] = [Vec3(500, 0, 0), Vec3(-500, 0, 0)]
        let size = CGSize(width: 1_000, height: 700)
        let fitted = Camera3D().fit(points: points, in: size)
        XCTAssertEqual(fitted.target, .zero)
        XCTAssertGreaterThan(fitted.distance, 450)
        XCTAssertLessThanOrEqual(fitted.distance, 9_000)
        XCTAssertEqual(fitted.yaw, -0.72)
        XCTAssertEqual(fitted.pitch, 0.30)

        var custom = Camera3D(yaw: 1.2, pitch: -0.4)
        custom = custom.fit(points: points, in: size, keepAngles: true)
        XCTAssertEqual(custom.yaw, 1.2)
        XCTAssertEqual(custom.pitch, -0.4)

        let empty = Camera3D(yaw: 1, pitch: 0.5, distance: 100)
        let fittedEmpty = empty.fit(points: [], in: size)
        XCTAssertEqual(fittedEmpty.target, .zero)
        XCTAssertEqual(fittedEmpty.distance, 1_500)
        XCTAssertEqual(fittedEmpty.yaw, 1)
        XCTAssertEqual(fittedEmpty.pitch, 0.5)
    }

    func testPanDeltaIsProportionalToDistance() {
        let size = CGSize(width: 1_000, height: 600)
        let near = Camera3D(distance: 800)
        let far = Camera3D(distance: 1_600)
        let translation = CGSize(width: 100, height: 50)
        let nearDelta = near.panDelta(screenTranslation: translation, size: size)
        let farDelta = far.panDelta(screenTranslation: translation, size: size)
        XCTAssertEqual(farDelta.length, nearDelta.length * 2, accuracy: 0.01)
        XCTAssertEqual(near.panDelta(screenTranslation: .zero, size: size), .zero)
    }
}

final class MapProjectionTests: XCTestCase {

    func testFlatProjectionUsesCameraTransform() throws {
        let projection = MapProjection(
            camera: Camera(center: Vec2(10, 20), zoom: 2),
            camera3D: Camera3D(),
            modeBlend: 0,
            size: CGSize(width: 1_000, height: 600),
            positions2D: ["a": Vec2(10, 20), "b": Vec2(60, 70)],
            positions3D: [:]
        )
        let center = try XCTUnwrap(projection.project(nodeID: "a"))
        XCTAssertEqual(center.point, CGPoint(x: 500, y: 300))
        XCTAssertEqual(center.depth, 0)
        XCTAssertEqual(center.scale, 1)
        XCTAssertEqual(projection.easedBlend, 0)
        XCTAssertEqual(projection.spatialAlpha, 0)

        let offset = try XCTUnwrap(projection.project(nodeID: "b"))
        XCTAssertEqual(offset.point, CGPoint(x: 600, y: 400))
        XCTAssertNil(projection.project(nodeID: "missing"))
    }

    func testBlendInterpolatesBetweenFlatAndSpatial() throws {
        let camera3D = Camera3D()
        let projection = MapProjection(
            camera: .identity,
            camera3D: camera3D,
            modeBlend: 1,
            size: CGSize(width: 1_000, height: 600),
            positions2D: ["a": .zero],
            positions3D: ["a": .zero]
        )
        XCTAssertEqual(projection.easedBlend, 1)
        let point = try XCTUnwrap(projection.project(nodeID: "a"))
        XCTAssertEqual(point.point.x, 500, accuracy: 0.001)
        XCTAssertEqual(point.point.y, 300, accuracy: 0.001)
        XCTAssertEqual(point.depth, camera3D.distance, accuracy: 0.001)
        XCTAssertEqual(projection.project(world: .zero)?.depth ?? 0, camera3D.distance, accuracy: 0.001)
    }

    func testMidBlendFallsBackWhen3DPositionIsUnavailable() {
        let projection = MapProjection(
            camera: .identity,
            camera3D: Camera3D(),
            modeBlend: 0.4,
            size: CGSize(width: 1_000, height: 600),
            positions2D: ["a": .zero],
            positions3D: [:]
        )
        XCTAssertNotNil(projection.project(nodeID: "a"))
        XCTAssertEqual(projection.easedBlend, 0.352, accuracy: 0.001)

        let mostlySpatial = MapProjection(
            camera: .identity,
            camera3D: Camera3D(),
            modeBlend: 0.6,
            size: CGSize(width: 1_000, height: 600),
            positions2D: ["a": .zero],
            positions3D: [:]
        )
        XCTAssertNil(mostlySpatial.project(nodeID: "a"))
    }
}
