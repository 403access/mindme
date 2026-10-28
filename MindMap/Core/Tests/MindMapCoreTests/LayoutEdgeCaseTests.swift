import XCTest
@testable import MindMapCore

// MARK: - Manual graph fixtures

private func makeNode(
    _ id: String,
    kind: NodeKind,
    groupID: String? = nil,
    threadID: String? = nil,
    parentID: String? = nil,
    weight: Double = 1
) -> MindMapNode {
    MindMapNode(
        id: id,
        kind: kind,
        label: id,
        groupID: groupID,
        threadID: threadID,
        parentID: parentID,
        weight: weight
    )
}

private func makeEdge(_ source: String, _ target: String, _ kind: EdgeKind) -> MindMapEdge {
    MindMapEdge(source: source, target: target, kind: kind)
}

private func makeGraph(
    nodes: [MindMapNode],
    edges: [MindMapEdge] = [],
    threadCount: Int = 1
) -> MindMapGraph {
    MindMapGraph(
        nodes: nodes,
        edges: edges,
        stats: GraphStats(threadCount: threadCount, groupCount: nodes.filter { $0.kind == .group }.count)
    )
}

// MARK: - 2D layout edge cases

final class GraphLayoutEdgeCaseTests: XCTestCase {

    func testEmptyAndRootOnlyGraphs() {
        XCTAssertEqual(GraphLayout.anchors(for: .empty), ["root": .zero])

        let rootOnly = makeGraph(nodes: [makeNode("root", kind: .root)], threadCount: 0)
        XCTAssertEqual(GraphLayout.anchors(for: rootOnly), ["root": .zero])
    }

    func testGroupWithoutThreadsStillGetsAFiniteAnchor() throws {
        let graph = makeGraph(nodes: [
            makeNode("root", kind: .root),
            makeNode("group", kind: .group)
        ], edges: [makeEdge("root", "group", .rootGroup)])

        let anchors = GraphLayout.anchors(for: graph)
        XCTAssertEqual(anchors.count, 2)
        let group = try XCTUnwrap(anchors["group"])
        XCTAssertGreaterThan(group.length, 0)
        XCTAssertTrue(group.x.isFinite)
        XCTAssertTrue(group.y.isFinite)
    }

    func testFlatGroupAnchorsThreadsOutsideTheHub() throws {
        let graph = makeGraph(nodes: [
            makeNode("root", kind: .root),
            makeNode("group", kind: .group),
            makeNode("thread:1", kind: .thread, groupID: "group", threadID: "1"),
            makeNode("thread:2", kind: .thread, groupID: "group", threadID: "2")
        ], edges: [
            makeEdge("root", "group", .rootGroup),
            makeEdge("group", "thread:1", .groupThread),
            makeEdge("group", "thread:2", .groupThread)
        ])

        let anchors = GraphLayout.anchors(for: graph)
        XCTAssertEqual(anchors.count, 4)
        let hub = try XCTUnwrap(anchors["group"])
        for thread in ["thread:1", "thread:2"] {
            let point = try XCTUnwrap(anchors[thread])
            XCTAssertGreaterThan(point.length, hub.length)
            XCTAssertTrue(point.x.isFinite)
            XCTAssertTrue(point.y.isFinite)
        }
    }

    func testHierarchyPlacesRegionsThenChildrenThenThreads() throws {
        let graph = makeGraph(nodes: [
            makeNode("root", kind: .root),
            makeNode("region", kind: .group),
            makeNode("child", kind: .group, parentID: "region"),
            makeNode("thread:1", kind: .thread, groupID: "child", threadID: "1")
        ], edges: [
            makeEdge("root", "region", .rootGroup),
            makeEdge("region", "child", .regionGroup),
            makeEdge("child", "thread:1", .groupThread)
        ])

        let anchors = GraphLayout.anchors(for: graph)
        XCTAssertEqual(anchors.count, 4)
        let region = try XCTUnwrap(anchors["region"])
        let child = try XCTUnwrap(anchors["child"])
        let thread = try XCTUnwrap(anchors["thread:1"])
        XCTAssertGreaterThan(region.length, 0)
        XCTAssertGreaterThan(child.length, region.length)
        XCTAssertGreaterThan(thread.length, child.length)
    }

    func testHierarchyWithoutChildrenPlacesDirectThreads() throws {
        let graph = makeGraph(nodes: [
            makeNode("root", kind: .root),
            makeNode("region", kind: .group),
            makeNode("thread:1", kind: .thread, groupID: "region", threadID: "1")
        ], edges: [
            makeEdge("root", "region", .rootGroup),
            makeEdge("region", "thread:1", .groupThread)
        ])

        let anchors = GraphLayout.anchors(for: graph)
        XCTAssertEqual(anchors.count, 3)
        XCTAssertGreaterThan(try XCTUnwrap(anchors["thread:1"]).length, 0)
    }

    func testTagWithoutNeighboursIsPlacedOnTheOuterRing() throws {
        let graph = makeGraph(nodes: [
            makeNode("root", kind: .root),
            makeNode("group", kind: .group),
            makeNode("tag:lonely", kind: .tag)
        ])

        let anchors = GraphLayout.anchors(for: graph)
        let tag = try XCTUnwrap(anchors["tag:lonely"])
        XCTAssertGreaterThan(tag.length, 235, "isolated tags sit outside the hub radius")
        XCTAssertTrue(tag.x.isFinite)
        XCTAssertTrue(tag.y.isFinite)
    }

    func testTagAveragesNeighbourPositions() throws {
        let graph = makeGraph(nodes: [
            makeNode("root", kind: .root),
            makeNode("group", kind: .group),
            makeNode("thread:1", kind: .thread, groupID: "group", threadID: "1"),
            makeNode("tag:shared", kind: .tag)
        ], edges: [
            makeEdge("root", "group", .rootGroup),
            makeEdge("group", "thread:1", .groupThread),
            makeEdge("thread:1", "tag:shared", .threadTag)
        ])

        let anchors = GraphLayout.anchors(for: graph)
        let tag = try XCTUnwrap(anchors["tag:shared"])
        XCTAssertGreaterThan(tag.length, 0)
        XCTAssertTrue(tag.x.isFinite)
        XCTAssertTrue(tag.y.isFinite)
    }

    func testAllAnchorsAreFiniteForDemoGraph() {
        let demo = DemoData.make(now: Date(timeIntervalSince1970: 1_780_000_000))
        let graph = GraphBuilder.build(library: demo, filters: .default)
        let anchors = GraphLayout.anchors(for: graph)
        XCTAssertEqual(anchors.count, graph.nodes.count)
        for (id, point) in anchors {
            XCTAssertTrue(point.x.isFinite, id)
            XCTAssertTrue(point.y.isFinite, id)
            XCTAssertTrue(point.length < 20_000, id)
        }
    }
}

// MARK: - 3D layout edge cases

final class GraphLayout3DEdgeCaseTests: XCTestCase {

    func testEmptyAndRootOnlyGraphs() {
        XCTAssertEqual(GraphLayout3D.anchors(for: .empty), ["root": .zero])
        let rootOnly = makeGraph(nodes: [makeNode("root", kind: .root)], threadCount: 0)
        XCTAssertEqual(GraphLayout3D.anchors(for: rootOnly), ["root": .zero])
    }

    func testFlatGroupAndThreadAreFinite() throws {
        let graph = makeGraph(nodes: [
            makeNode("root", kind: .root),
            makeNode("group", kind: .group),
            makeNode("thread:1", kind: .thread, groupID: "group", threadID: "1")
        ], edges: [
            makeEdge("root", "group", .rootGroup),
            makeEdge("group", "thread:1", .groupThread)
        ])

        let anchors = GraphLayout3D.anchors(for: graph)
        XCTAssertEqual(anchors.count, 3)
        XCTAssertGreaterThan(try XCTUnwrap(anchors["group"]).length, 0)
        XCTAssertGreaterThan(try XCTUnwrap(anchors["thread:1"]).length, 0)
        for point in anchors.values {
            XCTAssertTrue(point.x.isFinite)
            XCTAssertTrue(point.y.isFinite)
            XCTAssertTrue(point.z.isFinite)
        }
    }

    func testHierarchyPlacesRegionsChildrenAndThreads() throws {
        let graph = makeGraph(nodes: [
            makeNode("root", kind: .root),
            makeNode("region", kind: .group),
            makeNode("child", kind: .group, parentID: "region"),
            makeNode("thread:1", kind: .thread, groupID: "child", threadID: "1")
        ], edges: [
            makeEdge("root", "region", .rootGroup),
            makeEdge("region", "child", .regionGroup),
            makeEdge("child", "thread:1", .groupThread)
        ])

        let anchors = GraphLayout3D.anchors(for: graph)
        XCTAssertEqual(anchors.count, 4)
        XCTAssertGreaterThan(try XCTUnwrap(anchors["region"]).length, 0)
        XCTAssertGreaterThan(try XCTUnwrap(anchors["child"]).length, 0)
        XCTAssertGreaterThan(try XCTUnwrap(anchors["thread:1"]).length, 0)
        XCTAssertEqual(anchors, GraphLayout3D.anchors(for: graph))
    }

    func testTagWithoutNeighboursIsPlacedOutward() throws {
        let graph = makeGraph(nodes: [
            makeNode("root", kind: .root),
            makeNode("group", kind: .group),
            makeNode("tag:lonely", kind: .tag)
        ])

        let anchors = GraphLayout3D.anchors(for: graph)
        XCTAssertGreaterThan(try XCTUnwrap(anchors["tag:lonely"]).length, 0)
    }

    func testAllSpatialAnchorsAreFiniteForDemoGraph() {
        let demo = DemoData.make(now: Date(timeIntervalSince1970: 1_780_000_000))
        let graph = GraphBuilder.build(library: demo, filters: .default)
        let anchors = GraphLayout3D.anchors(for: graph)
        XCTAssertEqual(anchors.count, graph.nodes.count)
        for (id, point) in anchors {
            XCTAssertTrue(point.length.isFinite, id)
            XCTAssertLessThan(point.length, 20_000, id)
        }
    }
}

// MARK: - Force simulation edge cases

final class ForceLayoutEdgeCaseTests: XCTestCase {

    private func sampleGraph(includeTags: Bool = false) -> MindMapGraph {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let threads = (0..<4).map { index in
            ConversationThread(
                id: "t\(index)",
                provider: .chatgpt,
                title: "Thread \(index)",
                createdAt: start,
                updatedAt: start.addingTimeInterval(TimeInterval(index)),
                messages: [
                    ChatMessage(id: "m\(index)", role: .user, text: "shared keyword number \(index)")
                ]
            )
        }
        var filters = GraphFilters.default
        filters.includeTags = includeTags
        return GraphBuilder.build(library: ThreadLibrary(threads: threads), filters: filters)
    }

    func testInitialBodiesAndSpringsMatchTheGraph() {
        let graph = sampleGraph()
        let layout = ForceLayout(graph: graph)
        XCTAssertEqual(layout.bodies.count, graph.nodes.count)
        XCTAssertEqual(layout.springs.count, graph.edges.count)
        XCTAssertEqual(layout.steps, 0)
        XCTAssertEqual(layout.settledFrames, 0)
        XCTAssertEqual(layout.positions.count, graph.nodes.count)
    }

    func testRootIsFixedAtTheOriginAndPreviousPositionsAreHonoured() throws {
        let graph = sampleGraph()
        let anchors = GraphLayout.anchors(for: graph)
        let previous = ["root": Vec2(5, 6)]
        var layout = ForceLayout(graph: graph, anchors: anchors, previousPositions: previous)

        let root = try XCTUnwrap(layout.bodies.first { $0.kind == .root })
        XCTAssertEqual(root.position, Vec2(5, 6))
        XCTAssertTrue(root.fixed)
        XCTAssertEqual(root.stiffness, 0)
        XCTAssertEqual(root.velocity, .zero)

        layout.wake()
        XCTAssertEqual(layout.settledFrames, 0)
        XCTAssertEqual(layout.bodies.first { $0.kind == .root }?.velocity, .zero)

        for _ in 0..<50 {
            layout.step(dt: 1.0 / 60.0)
        }
        XCTAssertEqual(layout.bodies.first { $0.kind == .root }?.position, Vec2(5, 6))
    }

    func testSimulationStaysFiniteAndSettles() {
        let graph = sampleGraph()
        var layout = ForceLayout(graph: graph)
        layout.wake()
        for _ in 0..<600 {
            layout.step(dt: 1.0 / 60.0)
        }
        XCTAssertEqual(layout.steps, 600)
        XCTAssertTrue(layout.lastMaxSpeed.isFinite)
        for body in layout.bodies {
            XCTAssertTrue(body.position.x.isFinite)
            XCTAssertTrue(body.position.y.isFinite)
            XCTAssertLessThan(body.velocity.length, 900.001)
            XCTAssertLessThan(body.position.length, 10_000)
        }
        XCTAssertTrue(layout.isSettled, "600 frames should be enough for a small graph")
    }

    func testDeltaTimeIsClamped() {
        let graph = sampleGraph()
        let anchors = GraphLayout.anchors(for: graph)

        var fast = ForceLayout(graph: graph, anchors: anchors)
        fast.step(dt: 100)
        var normal = ForceLayout(graph: graph, anchors: anchors)
        normal.step(dt: 1.0 / 30.0)
        XCTAssertEqual(fast.positions, normal.positions)

        var tiny = ForceLayout(graph: graph, anchors: anchors)
        tiny.step(dt: 0)
        var floor = ForceLayout(graph: graph, anchors: anchors)
        floor.step(dt: 1.0 / 240.0)
        XCTAssertEqual(tiny.positions, floor.positions)
    }

    func testEmptyGraphStepIsANoOp() {
        var layout = ForceLayout(graph: .empty)
        XCTAssertTrue(layout.bodies.isEmpty)
        layout.wake()
        layout.step(dt: 1.0 / 60.0)
        XCTAssertEqual(layout.steps, 0)
        XCTAssertTrue(layout.positions.isEmpty)
        XCTAssertFalse(layout.isSettled)
    }

    func testTagBodiesAreSofterThanThreads() throws {
        let graph = sampleGraph(includeTags: true)
        let layout = ForceLayout(graph: graph)
        let tag = try XCTUnwrap(layout.bodies.first { $0.kind == .tag })
        let thread = try XCTUnwrap(layout.bodies.first { $0.kind == .thread })
        XCTAssertLessThan(tag.stiffness, thread.stiffness)
        XCTAssertLessThan(tag.collisionRadius, thread.collisionRadius)
    }
}
