import Foundation

/// A small, dependency-free 2D vector used by the layout engine.
/// Kept separate from CoreGraphics so the core can be shared with iOS.
public struct Vec2: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double = 0, _ y: Double = 0) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public var length: Double { (x * x + y * y).squareRoot() }
    public var lengthSquared: Double { x * x + y * y }
    public var angle: Double { atan2(y, x) }

    public var normalized: Vec2 {
        let l = length
        guard l > 0.000_001 else { return .zero }
        return Vec2(x / l, y / l)
    }

    public func rotated(by radians: Double) -> Vec2 {
        let c = cos(radians), s = sin(radians)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }

    public func distance(to other: Vec2) -> Double { (self - other).length }
    public func distanceSquared(to other: Vec2) -> Double { (self - other).lengthSquared }

    public static func + (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x + r.x, l.y + r.y) }
    public static func - (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x - r.x, l.y - r.y) }
    public static func * (l: Vec2, r: Double) -> Vec2 { Vec2(l.x * r, l.y * r) }
    public static func * (l: Double, r: Vec2) -> Vec2 { r * l }
    public static func / (l: Vec2, r: Double) -> Vec2 { Vec2(l.x / r, l.y / r) }
    public static func += (l: inout Vec2, r: Vec2) { l = l + r }
    public static func -= (l: inout Vec2, r: Vec2) { l = l - r }

    public func clampedLength(_ maxLength: Double) -> Vec2 {
        let l = length
        guard l > maxLength, l > 0 else { return self }
        return self * (maxLength / l)
    }
}
