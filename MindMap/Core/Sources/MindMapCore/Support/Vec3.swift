import Foundation

/// Three-dimensional vector used by the spatial (3D) layout and camera.
public struct Vec3: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)
    public static let up = Vec3(0, 1, 0)

    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public var lengthSquared: Double { x * x + y * y + z * z }

    public var normalized: Vec3 {
        let l = length
        guard l > 0.000_001 else { return .zero }
        return Vec3(x / l, y / l, z / l)
    }

    public func dot(_ other: Vec3) -> Double { x * other.x + y * other.y + z * other.z }

    public func cross(_ other: Vec3) -> Vec3 {
        Vec3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    public func distance(to other: Vec3) -> Double { (self - other).length }
    public func distanceSquared(to other: Vec3) -> Double { (self - other).lengthSquared }

    public var vec2: Vec2 { Vec2(x, y) }

    public static func + (l: Vec3, r: Vec3) -> Vec3 { Vec3(l.x + r.x, l.y + r.y, l.z + r.z) }
    public static func - (l: Vec3, r: Vec3) -> Vec3 { Vec3(l.x - r.x, l.y - r.y, l.z - r.z) }
    public static func * (l: Vec3, r: Double) -> Vec3 { Vec3(l.x * r, l.y * r, l.z * r) }
    public static func * (l: Double, r: Vec3) -> Vec3 { r * l }
    public static func / (l: Vec3, r: Double) -> Vec3 { Vec3(l.x / r, l.y / r, l.z / r) }
    public static func += (l: inout Vec3, r: Vec3) { l = l + r }
    public static func -= (l: inout Vec3, r: Vec3) { l = l - r }

    public func clampedLength(_ maxLength: Double) -> Vec3 {
        let l = length
        guard l > maxLength, l > 0 else { return self }
        return self * (maxLength / l)
    }
}
