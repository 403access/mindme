import Foundation

/// A small force-directed relaxation tuned for constellation maps.
/// Repulsion is grid-accelerated so hundreds of nodes animate at 60 fps.
public struct ForceLayout {

    public struct Body: Identifiable, Sendable {
        public var id: String
        public var kind: NodeKind
        public var position: Vec2
        public var velocity: Vec2
        public var anchor: Vec2
        public var stiffness: Double
        public var collisionRadius: Double
        public var fixed: Bool
    }

    public struct Spring: Sendable {
        public var a: Int
        public var b: Int
        public var restLength: Double
        public var strength: Double
    }

    public private(set) var bodies: [Body]
    public private(set) var springs: [Spring]
    private var indexByID: [String: Int]
    public private(set) var settledFrames: Int = 0
    public private(set) var lastMaxSpeed: Double = 0
    public private(set) var steps: Int = 0

    private let repulsion: Double
    private let cellSize = 140.0

    public init(
        graph: MindMapGraph,
        anchors: [String: Vec2]? = nil,
        previousPositions: [String: Vec2] = [:],
        repulsion: Double = 5200
    ) {
        let resolvedAnchors = anchors ?? GraphLayout.anchors(for: graph)
        self.repulsion = repulsion

        var bodies: [Body] = []
        var indexByID: [String: Int] = [:]
        bodies.reserveCapacity(graph.nodes.count)

        for (index, node) in graph.nodes.enumerated() {
            let anchor = resolvedAnchors[node.id] ?? .zero
            let previous = previousPositions[node.id]
            let jitter = Self.jitter(for: node.id, kind: node.kind)
            let position = previous ?? (anchor + jitter)

            let stiffness: Double
            let radius: Double
            switch node.kind {
            case .root:
                stiffness = 0
                radius = 92
            case .group:
                stiffness = 2.15
                radius = 84
            case .thread:
                stiffness = 1.55
                radius = 42
            case .tag:
                stiffness = 0.32
                radius = 32
            }

            indexByID[node.id] = index
            bodies.append(Body(
                id: node.id,
                kind: node.kind,
                position: position,
                velocity: .zero,
                anchor: anchor,
                stiffness: stiffness,
                collisionRadius: radius,
                fixed: node.kind == .root
            ))
        }

        var springs: [Spring] = []
        for edge in graph.edges {
            guard let a = indexByID[edge.source], let b = indexByID[edge.target] else { continue }
            let rest: Double
            let strength: Double
            switch edge.kind {
            case .rootGroup: rest = 300; strength = 0.28
            case .regionGroup: rest = 210; strength = 0.42
            case .groupThread: rest = 118; strength = 0.52
            case .threadTag: rest = 72; strength = 0.34
            }
            springs.append(Spring(a: a, b: b, restLength: rest, strength: strength))
        }

        self.bodies = bodies
        self.springs = springs
        self.indexByID = indexByID
    }

    public var positions: [String: Vec2] {
        Dictionary(uniqueKeysWithValues: bodies.map { ($0.id, $0.position) })
    }

    public var isSettled: Bool {
        settledFrames > 20
    }

    public mutating func wake() {
        settledFrames = 0
        for i in bodies.indices where !bodies[i].fixed {
            bodies[i].velocity += Vec2(
                Double(StableID.hash(bodies[i].id) % 100) / 100.0 - 0.5,
                Double(StableID.hash(bodies[i].id + "y") % 100) / 100.0 - 0.5
            )
        }
    }

    public mutating func step(dt rawDT: Double) {
        guard !bodies.isEmpty else { return }
        let dt = min(max(rawDT, 1.0 / 240.0), 1.0 / 30.0)

        var forces = [Vec2](repeating: .zero, count: bodies.count)

        // Spatial grid for short-range repulsion + collision.
        var grid: [Int64: [Int]] = [:]
        grid.reserveCapacity(bodies.count * 2)
        for (index, body) in bodies.enumerated() {
            let key = cellKey(body.position)
            grid[key, default: []].append(index)
        }

        for i in bodies.indices {
            let body = bodies[i]
            let cx = Int((body.position.x / cellSize).rounded(.down))
            let cy = Int((body.position.y / cellSize).rounded(.down))
            // 5x5 cells: guarantees every pair within the 190-unit cutoff is
            // considered, including 168-unit-wide hub collisions.
            for gx in (cx - 2)...(cx + 2) {
                for gy in (cy - 2)...(cy + 2) {
                    guard let bucket = grid[Self.pack(gx, gy)] else { continue }
                    for j in bucket where j > i {
                        let delta = bodies[j].position - body.position
                        let distanceSquared = max(delta.lengthSquared, 0.01)
                        if distanceSquared > 190 * 190 { continue }
                        let distance = distanceSquared.squareRoot()
                        let direction = delta / distance
                        let repel = repulsion / max(distanceSquared, 250)
                        let overlap = body.collisionRadius + bodies[j].collisionRadius - distance
                        let collision = overlap > 0 ? overlap * 3.2 : 0
                        let magnitude = repel + collision
                        forces[i] -= direction * magnitude
                        forces[j] += direction * magnitude
                    }
                }
            }
        }

        // Anchor springs.
        for i in bodies.indices where !bodies[i].fixed {
            let delta = bodies[i].anchor - bodies[i].position
            forces[i] += delta * bodies[i].stiffness
        }

        // Edge springs.
        for spring in springs {
            guard !bodies[spring.a].fixed || !bodies[spring.b].fixed else { continue }
            let delta = bodies[spring.b].position - bodies[spring.a].position
            let distance = max(delta.length, 0.001)
            let direction = delta / distance
            let stretch = distance - spring.restLength
            let magnitude = stretch * spring.strength
            if !bodies[spring.a].fixed { forces[spring.a] += direction * magnitude }
            if !bodies[spring.b].fixed { forces[spring.b] -= direction * magnitude }
        }

        var maxSpeed = 0.0
        for i in bodies.indices where !bodies[i].fixed {
            var velocity = bodies[i].velocity + forces[i] * dt
            // Critical-ish damping, per-kind.
            let damping: Double
            switch bodies[i].kind {
            case .tag: damping = exp(-1.8 * dt)
            case .group: damping = exp(-3.6 * dt)
            default: damping = exp(-3.1 * dt)
            }
            velocity = velocity * damping
            if velocity.length > 900 { velocity = velocity.clampedLength(900) }
            bodies[i].velocity = velocity
            bodies[i].position += velocity * dt
            maxSpeed = max(maxSpeed, velocity.length)
        }

        steps += 1
        lastMaxSpeed = maxSpeed
        if maxSpeed < 2.5 {
            settledFrames += 1
        } else {
            settledFrames = 0
        }
    }

    // MARK: - Grid

    private func cellKey(_ position: Vec2) -> Int64 {
        Self.pack(Int((position.x / cellSize).rounded(.down)), Int((position.y / cellSize).rounded(.down)))
    }

    private static func pack(_ x: Int, _ y: Int) -> Int64 {
        (Int64(x) << 32) ^ (Int64(y) & 0xffff_ffff)
    }

    // MARK: - Jitter

    private static func jitter(for id: String, kind: NodeKind) -> Vec2 {
        let hash = StableID.hash(id)
        let angle = Double(hash % 6283) / 1000.0
        let magnitude: Double
        switch kind {
        case .root: magnitude = 0
        case .group: magnitude = 10
        case .thread: magnitude = 26
        case .tag: magnitude = 40
        }
        let radius = magnitude * (0.4 + Double((hash >> 16) % 1000) / 1000.0)
        return Vec2(cos(angle), sin(angle)) * radius
    }
}
