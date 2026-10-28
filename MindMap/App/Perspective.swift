import Foundation
import CoreGraphics
import MindMapCore

// MARK: - 3D camera

struct Camera3D: Equatable, Sendable {
    var yaw: Double
    var pitch: Double
    var distance: Double
    var target: Vec3
    var fov: Double

    init(
        yaw: Double = -0.72,
        pitch: Double = 0.30,
        distance: Double = 1_600,
        target: Vec3 = .zero,
        fov: Double = 0.88
    ) {
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
        self.target = target
        self.fov = fov
    }

    var position: Vec3 {
        let cp = cos(pitch)
        return target + Vec3(cp * cos(yaw), sin(pitch), cp * sin(yaw)) * distance
    }

    var forward: Vec3 { (target - position).normalized }

    var right: Vec3 {
        let r = forward.cross(.up)
        return r.length < 0.0001 ? Vec3(1, 0, 0) : r.normalized
    }

    var up: Vec3 { right.cross(forward).normalized }

    func project(_ point: Vec3, in size: CGSize) -> ProjectedPoint? {
        guard size.width > 1, size.height > 1 else { return nil }
        let eye = position
        let forward = self.forward
        let right = self.right
        let up = self.up
        let relative = point - eye
        let depth = relative.dot(forward)
        guard depth > 1 else { return nil }

        let focal = (Double(size.height) / 2) / tan(fov / 2)
        let screenX = Double(size.width) / 2 + relative.dot(right) * focal / depth
        let screenY = Double(size.height) / 2 - relative.dot(up) * focal / depth
        let scale = min(3.2, max(0.22, distance / depth))
        return ProjectedPoint(
            point: CGPoint(x: screenX, y: screenY),
            depth: depth,
            scale: scale
        )
    }

    func fit(points: [Vec3], in size: CGSize, keepAngles: Bool = false) -> Camera3D {
        guard !points.isEmpty else {
            var fallback = self
            fallback.target = .zero
            fallback.distance = 1_500
            return fallback
        }
        var radius: Double = 80
        for point in points {
            radius = max(radius, point.length)
        }

        let aspect = max(0.3, Double(size.width) / max(1, Double(size.height)))
        let verticalHalf = fov / 2
        let horizontalHalf = atan(tan(verticalHalf) * aspect)
        let halfAngle = min(verticalHalf, horizontalHalf)
        let distance = min(9_000, max(450, radius / max(0.15, sin(halfAngle)) * 1.05))

        var camera = self
        if !keepAngles {
            camera.yaw = -0.72
            camera.pitch = 0.30
        }
        camera.target = .zero
        camera.distance = distance
        return camera
    }
}

// MARK: - Projection

struct ProjectedPoint: Equatable {
    var point: CGPoint
    var depth: Double
    var scale: Double
}

struct MapProjection {
    var camera: Camera
    var camera3D: Camera3D
    var modeBlend: Double
    var size: CGSize
    var positions2D: [String: Vec2]
    var positions3D: [String: Vec3]

    var easedBlend: Double {
        let t = min(1, max(0, modeBlend))
        return t * t * (3 - 2 * t)
    }

    func project(nodeID: String) -> ProjectedPoint? {
        guard let p2 = positions2D[nodeID] else { return nil }
        let screen2D = CGPoint(
            x: size.width / 2 + (p2.x - camera.center.x) * camera.zoom,
            y: size.height / 2 + (p2.y - camera.center.y) * camera.zoom
        )
        if modeBlend <= 0.001 {
            return ProjectedPoint(point: screen2D, depth: 0, scale: 1)
        }
        guard let p3 = positions3D[nodeID], let projected = camera3D.project(p3, in: size) else {
            guard modeBlend < 0.5 else { return nil }
            return ProjectedPoint(point: screen2D, depth: 0, scale: 1)
        }
        let t = easedBlend
        let point = CGPoint(
            x: screen2D.x + (projected.point.x - screen2D.x) * t,
            y: screen2D.y + (projected.point.y - screen2D.y) * t
        )
        return ProjectedPoint(
            point: point,
            depth: projected.depth,
            scale: 1 + (projected.scale - 1) * t
        )
    }

    func project(world point: Vec3) -> ProjectedPoint? {
        camera3D.project(point, in: size)
    }

    var spatialAlpha: Double { easedBlend }
}

// MARK: - Camera helpers

extension Camera3D {
    /// Converts a screen-space drag into a target translation on the camera
    /// plane, using the average scene depth.
    func panDelta(screenTranslation: CGSize, size: CGSize) -> Vec3 {
        let focal = (Double(size.height) / 2) / tan(fov / 2)
        guard focal > 0 else { return .zero }
        let worldPerPixel = distance / focal
        let right = self.right
        let up = self.up
        return right * (-Double(screenTranslation.width) * worldPerPixel)
            + up * (Double(screenTranslation.height) * worldPerPixel)
    }
}
