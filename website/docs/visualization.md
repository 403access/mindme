---
title: Visualization
description: Graph model, keyword pipeline, 2D and 3D layouts, word clouds, cameras, renderer, and extension points.
---

# MINDME Visualization

How a library of imported conversations becomes the map you see. This is the
deep-dive companion to the [project README](https://github.com/403access/mindme#readme): the
graph model, the keyword pipeline, both layouts, the camera/projection stack, and the renderer.

**The default view is not a word cloud.** Words do not drive type size in the
constellation. Keywords become topology — small diamond *tag nodes* and, in
topic mode, group hubs — while the main visual object is a node-link
force-directed graph. Two opt-in cloud lenses expose the same filtered tags:
a free **word cloud** (⌘4) and a **hybrid cloud** (⌘5) that keeps the
constellation structure and anchors sized words to their tag nodes.

The keyboard shortcuts below refer to macOS. On iPhone the same lenses and camera controls are
on the map, and tap replaces click/hover for selection and inspection.

```
KeywordExtractor ──► tag nodes, topic hubs, inspector chips
                  ├► WordCloudLayout (⌘4, free spiral)
                  └► HybridWordLayout (⌘5, anchored to the map)
```

---

## 1. Pipeline at a glance

```
ThreadLibrary
   │  GraphFilters (providers, since, search, maxThreads)
   ▼
GraphBuilder.build(library:filters:topicAnalysis:)
   │  + KeywordExtractor.buildIndex
   │  + TopicClusterer (topic mode only)
   │  + TopicPipeline (region mode only)     Analysis/Topics/
   ▼
MindMapGraph { nodes, edges, stats, keywordsByThread }
   │
   ├─ GraphLayout.anchors      → Vec2 radial anchors      (2D)
   ├─ ForceLayout              → relaxed Vec2 positions   (2D)
   └─ GraphLayout3D.anchors    → deterministic Vec3 cloud (3D)
   ▼
GraphEngine (60 Hz timer, publishes RenderFrame)
   │  camera smoothing, mode crossfade, hit testing, ambient throttle
   ▼
MapProjection (2D → 3D blend)
   ▼
MapRenderer.draw(into: GraphicsContext)     App/MapRenderer.swift
   ▼
SwiftUI Canvas (GraphCanvasView)

MindMapGraph.tagNodes + weights
   ▼
WordCloudLayout (cached per filter/size)    App/WordCloudView.swift
   ▼
WordCloudRenderer.draw(into: GraphicsContext)   (⌘4)
   ▼
SwiftUI Canvas (WordCloudView)

MapProjection + MindMapGraph.tagNodes
   ▼
HybridLayoutCache (seeds + text metrics cached; re-placed on projection change)   App/HybridWords.swift
   ▼
MapRenderer (full skeleton) + HybridWordRenderer   (⌘5)
   ▼
SwiftUI Canvas (GraphCanvasView)
```

The core package is UI-independent; everything above `GraphEngine` is
deterministic and unit-tested without an app running.

---

## 2. Graph model

`MindMapGraph` (`Core/.../Graph/MindMapGraph.swift`) is a plain value type.

### Nodes

| Kind | ID pattern | Drawn as | Size driver | Colour |
| --- | --- | --- | --- | --- |
| `root` | `root` | hexagon, layered aura | fixed | accent cyan |
| `group` | `group:provider:*`, `group:topic:misc`, `group:era:*`, `topic:*`, `region:<topicID>` | ring hub, radius 23 pt | fixed radius, halo on select | provider colour, topic palette, or region colour |
| `thread` | `thread:<threadID>` | circle | `2.9 + min(3.6, weight × 0.95)` pt | provider colour |
| `tag` | `tag:<slug>` | diamond | `2.4 + min(2.2, weight × 0.35)` pt | fixed blue-grey |

Weights:

- thread `weight = 1 + min(3, log(1 + messageCount) × 0.55)`
- tag `weight = number of conversations using the keyword`
- group `weight = number of threads in the group`

### Edges

| Kind | Connects | Rest length | Spring strength | Render |
| --- | --- | --- | --- | --- |
| `rootGroup` | root → region/group | 300 | 0.28 | straight, provider tint |
| `regionGroup` | region → sub-region | 210 | 0.42 | gently curved |
| `groupThread` | group → thread | 118 | 0.52 | gently curved |
| `threadTag` | thread → tag | 72 | 0.34 | dashed `[1.5, 4.5]` |

Only `threadTag` edges cross group boundaries. That is the mechanism behind
"shared language bridges providers" — conversations are never merged, they are
linked through tag nodes.

### Focus path

`MindMapGraph.focusPath(for:)` returns the highlighted node set for the
selected or hovered node:

- **root** → everything
- **group** → itself, descendant groups (sub-regions), their threads and tags, root
- **thread** → itself, its group, its tags, root
- **tag** → itself, all threads carrying it, their groups, root

`MapRenderer` draws anything outside that set at low opacity (`isDimmed`), which
is what makes the selected constellation pop.

---

## 3. Grouping modes

`GraphBuilder` (`GraphBuilder.swift:36`) supports four ways to cut the same
library into hubs. The mode only changes group membership, not the node set.

| Mode | Hubs | Notes |
| --- | --- | --- |
| `provider` | one per `Provider` enum case present | hub colour = provider colour |
| `topic` | up to `min(14, max(6, 6 + n/24))` keyword clusters + `MISCELLANY` | see below |
| `region` | two levels: curated region → sub-region | `MindMapNode.parentID` + `regionGroup` edges |
| `era` | time buckets | monthly under 130 days, quarterly under 4 years, yearly beyond |

**Topic clustering** (`Analysis/TopicClusterer.swift`) is deterministic:

1. Sum keyword scores per term across threads.
2. Keep terms with document frequency ≥ 2.
3. Rank by `total × log(df + 1)`, drop near-duplicates where one term contains
   another with equal-or-higher df (e.g. `swift` vs `swiftui`).
4. Assign each thread to its highest-scoring selected term.
5. Drop clusters that end up with a single thread, reassign those threads (max
   2 passes), and put leftovers in `MISCELLANY`.

**Era buckets** use `updatedAt`, not `createdAt`, so active threads land in the
period they were last touched.

**Region grouping** (`Analysis/Topics/`) classifies *parts* of a conversation,
not just the whole thread:

1. `ConversationSegmenter` builds prompt+reply units and cuts where hashed
   embeddings diverge, vocabulary turns over, a time gap appears, or the prompt
   contains an explicit cue.
2. `TopicClassifier` scores each segment against `TopicTaxonomy.default` — a
   curated English/German seed spine (product, technology, legal, finance,
   design, research, operations, personal, philosophy). A parent prototype
   includes its descendants' vocabulary, so "kubernetes" still feeds Technology.
3. `TopicPipeline.viterbi` smooths the sequence (stay free, sibling cheap,
   cross-domain expensive).
4. Rollup weights segments by prompt length + 25% of answer length, producing a
   soft region distribution. A mixed project thread can be 60% technology and
   40% legal; the map attaches it to its largest sub-region, while the inspector
   shows every segment.
5. Profiles live in `~/Library/Application Support/MindMap/topics.json`, keyed
   by thread content hash and pipeline versions. Re-imports reuse unchanged
   threads. Classification fans out across cores but writes results by index,
   so output is byte-identical to a serial run.

Low-confidence text lands in `emerging` instead of a forced region. The
taxonomy is plain data; bump `TopicTaxonomy.default.version` when seeds change
to invalidate cached profiles. New regions are merged into an existing
`taxonomy.json` on launch without overwriting user renames or reseeds.

**Focused topic lenses** narrow the graph to a taxonomy root before the thread
cap is applied. `GraphFilters.topicRoots` + `topicShareThreshold` are applied in
`GraphBuilder.build` using the same cached `TopicAnalysis` that region grouping
uses, and threads are placed by their strongest leaf inside the lens rather than
their overall primary region. The formal-philosophy button (`⌘6`) is the built-in
preset: it sets region grouping, scopes to `philosophy` at a 0.5 share, and
groups Logic, Mathematics, Language, Mind, Epistemology, Metaphysics, and
Science.

**Spend heat** is an opt-in renderer overlay (`showSpend`, off by default).
OpenCode's importer copies session totals from `session_v2` and per-message
cost/tokens from `session_message.data`; trimmed sessions rescale visible
segment costs to the authoritative session total. `SegmentTopic` and
`TopicShare` carry cost, `MindMapNode.cost` aggregates by hub, and
`GraphStats.totalCost` / `costThreadCount` drive availability. When active:

- hub colour comes from `HUD.spendColor(sqrt(cost / maxGroupCost))`
- a circular gauge encodes the same intensity
- badges switch from thread counts to dollar totals
- thread nodes, group auras, and edges inherit the heat
- spend-bearing conversations are placed in their costliest sub-region
- the HUD strip reports total spend and the top region

The toggle lives in the Signal panel, the map's top-right corner, and
*Map → Show Spend Heat*. It refuses to turn on when the visible archive has no
cost data.

---

## 4. Keyword pipeline (why the words are diamonds)

`Analysis/KeywordExtractor.swift` is intentionally small: no embeddings, no
network, milliseconds per import.

### Tokenisation

- lowercase, split on non-alphanumerics
- keep 3–32 character tokens containing at least one letter
- drop English + German stopwords and a `weakTerms` list of generic AI words
  (`model`, `code`, `project`, …)
- light singularisation (`agents` → `agent`), with guards for `ss`, `us`, `is`,
  `as`, `os`, `ics`, `ous`

### Scoring

Per thread, tokens are counted per message and weighted:

```
frequency = 1 + log(min(count, 8))        // diminishing returns
score    += frequency × roleWeight

roleWeight: title 3.4 · user 1.8 · assistant 0.9
            system/tool skipped
```

Then multiplied by IDF and a title boost:

```
idf    = log((N + 1) / (df + 0.5)) + 1
score *= idf × (term in title ? 1.55 : 1.0)
```

Top `limitPerThread` keywords are kept (7 for the map, 6 by default in the
index API). Every user/assistant message is truncated before tokenising
(1,600 / 2,600 chars) to bound the work.

### How keywords enter the map

| Use | Threshold | File |
| --- | --- | --- |
| Tag nodes | keyword must be shared by ≥ 2 threads (≥ 3 when `n ≥ 45`) | `GraphBuilder.swift:109` |
| Tag budget | 42 / 60 / 90 tags at `< 80`, `≥ 80`, `≥ 200` threads | `GraphBuilder.swift:110` |
| Per-thread tags | top 5 qualifying keywords | `GraphBuilder.swift:123` |
| Topic hubs | clustered terms, see §3 | `TopicClusterer.swift` |
| Inspector chips | `graph.keywordsByThread` | `DetailPanelView.swift` |

The tag budget is the readability guard: a large archive produces thousands of
candidate keywords, so only the highest-document-frequency, highest-scoring ones
become nodes.

---

## 5. 2D layout

Two stages, both in the core package.

### 5.1 Deterministic anchors — `GraphLayout.swift`

```
hubRadius = 235 + 8.5 × √threadCount
sector    = (2π − 0.10×groupCount) × groupWeight / totalWeight
hub       = (cos θ, sin θ) × hubRadius
```

Threads hang below their hub in rows:

```
perRow = min(12, max(7, ⌈√(count × 1.4)⌉))
radius = hubRadius + 74 + row × 54 + (row / (rows−1)) × 8
angle  = hubAngle + (t − 0.5) × spread + stagger
spread = min(2.5, max(0.34, sector × 0.86))
```

This guarantees a legible starting picture, including the degenerate
single-provider case: one wide fountain rather than a narrow plume.

### 5.2 Relaxation — `ForceLayout.swift`

The simulation is a small custom solver, not a general physics engine.

| Force | Value |
| --- | --- |
| Repulsion | `5200 / max(d², 250)`, cutoff 190 units |
| Collision | `overlap × 3.2` using per-kind radii 92 / 84 / 42 / 32 |
| Anchor spring | root 0 · group 2.15 · thread 1.55 · tag 0.32 |
| Edge springs | see §2 |
| Damping | `exp(−3.6 dt)` groups, `exp(−1.8 dt)` tags, `exp(−3.1 dt)` others |
| Max speed | 900 units/s |

Short-range work is grid-accelerated: bodies are bucketed into 140-unit cells
and each body checks a 5×5 neighbourhood, so hundreds of nodes stay cheap.
`dt` is clamped to `[1/240, 1/30]` to survive a stalled run loop.

Settling: `maxSpeed < 2.5` for more than 20 frames. `GraphEngine` also caps the
simulation at 360 steps (~6 s at 60 Hz) regardless.

Determinism comes from `StableID.hash` for jitter, tie-breaking, pulse phases,
and label priority — re-filtering does not reshuffle the map.

---

## 6. 3D layout

`GraphLayout3D.swift` is fully deterministic and static; there is no 3D
simulation to run. Orbiting only re-projects fixed points.

```
hubRadius   = 330 + 7 × √threadCount
hub[i]      = fibonacciSphere(i, groupCount) × hubRadius
cloudRadius = 100 + 9 × √children
thread      = hub + fibonacciSphere(j, count) × cloudRadius × jitter(0.78…1.24)
tag         = mean(neighbour positions) + direction × 26
```

Groups sit on a Fibonacci sphere so every hub gets its own corner of space
instead of sharing a flat ring. Threads are pushed at least `0.42 × hubRadius`
from the origin so no cloud swallows the root. Tags are placed at the centroid
of the conversations that share them, then nudged outward; if a tag has no
resolved neighbours it falls back to a hashed direction at `0.8 × hubRadius`.

The same `MindMapGraph` feeds both layouts, so tag diamonds keep their identity
across the toggle.

---

## 7. Camera and projection

### 2D camera — `Camera` in `GraphEngine.swift`

- state: `center: Vec2`, `zoom`
- interactive zoom clamp `0.16 … 2.8`
- fit clamp `0.22 … 1.4`, with padding `clamp(10% of min view dimension, 48…92)`
- smoothing: `center += (target − center) × (1 − e^(−9.5 dt))`, zoom interpolated
  in log space

### 3D camera — `Camera3D` in `Perspective.swift`

- state: `yaw`, `pitch`, `distance`, `target`, `fov = 0.88 rad`
- default pose: yaw `−0.72`, pitch `0.30`, distance `1600`
- pitch clamp `±1.25 rad`; distance clamp `280 … 7000`
- projection: pinhole with `focal = (height/2) / tan(fov/2)`
- per-node depth scale `distance / depth`, clamped `0.22 … 3.2`
- `fit(points:in:keepAngles:)` computes a distance from the scene radius and the
  smaller of the vertical/horizontal half-FOV, clamped `450 … 9000`

### Crossfade

`MapProjection` blends the 2D screen position with the 3D projected position
using `modeBlend`, eased with smoothstep `t²(3 − 2t)`. The blend eases toward its
target at `1 − e^(−7 dt)`, so toggling 2D/3D is a camera move, not a cut. Nodes
whose 3D projection lands behind the camera drop out once `modeBlend ≥ 0.5`.

---

## 8. Renderer

`MapRenderer.draw` (`App/MapRenderer.swift:44`) runs fixed passes:

1. group auras (radial gradients sized to the cluster)
2. 2D grid + orbit rings (fade out in spatial mode)
3. 3D floor + spatial orbit guides (fade in)
4. edges
5. nodes (depth-sorted when `modeBlend > 0.01`)
6. labels

### Screen-space invariant

Node radii, diamonds, line widths, and fonts are drawn in screen pixels. Camera
zoom changes spacing only, never legibility. In 3D, `drawNodeScaled` applies the
projected depth scale around the node's own centre so shapes grow/shrink without
drifting.

### Depth cues (3D)

- draw order: far → near
- alpha: `brightness = clamp(0.42 + scale × 0.62, 0.40, 1.0)`
- edges scale by average endpoint depth
- off-screen culling keeps a 240 pt margin so edges do not pop at the border

### Edges and pulses

- highlighted edges: 1.15 pt + 5.5 pt glow; idle edges 0.65 pt at ~11% alpha
- unfocused edges drop to 4% white
- flow pulses: 14 budget idle, 90 when a path is focused; speed 0.10 (root→group)
  / 0.16 (others); skipped entirely when **MOTION** is off

### Labels

Labels are deliberately conservative to avoid a hairball.

| Node | Shown when (2D) | Shown when (3D) |
| --- | --- | --- |
| thread | selected/hovered/search-matched, or zoom ≥ 0.98 if in focus path, or zoom ≥ 1.35 | selected/hovered/search-matched |
| tag | selected, or zoom ≥ 1.7 and weight ≥ 4 | selected only |
| group | always, drawn toward the root | always |

Placement is greedy: candidates are sorted by priority (selected 1000, hovered
900, top-6 threads by weight 44, otherwise 10 + weight), then a label is skipped
if its rect intersects an already-placed rect. Backgrounds are filled at
55–82% opacity so labels survive over edges.

### Highlight vs. dim

`focusID = selectedNodeID ?? hoveredNodeID`. The focus path is resolved once per
frame in `GraphCanvasView` and passed into `MapRenderer`, so per-edge and
per-node checks are set lookups; everything else is dimmed rather than removed,
preserving spatial context.

Search reuses the same path mechanism without rebuilding the graph. `AppModel`
resolves the query against the library after a 90 ms debounce and publishes
`searchMatchNodeIDs` (amber-ringed threads), `searchHighlightNodeIDs` (their
hubs, tags, and root), and `searchWordIDs` (tags for the cloud lenses). When no
node is selected or hovered, that path becomes the focus set, so the full map
stays visible while non-matches dim. Isolate mode instead feeds the query into
`GraphFilters` and rebuilds the graph, exactly like the source/time filters.

---

## 9. Cloud modes

Both cloud lenses read `MindMapGraph.tagNodes` — the same nodes the map draws
as diamonds, already filtered by source, time window, and search. Each tag’s
`weight` is the number of conversations sharing that keyword. Both enable
`showTags` automatically; turning tags off while a cloud is open shows an
explanatory empty state.

| Mode | Shortcut | Structure | Layout lives in |
| --- | --- | --- | --- |
| free word cloud | ⌘4 | standalone spiral | `WordCloudView.swift` |
| hybrid cloud | ⌘5 | constellation skeleton + anchored words | `HybridWords.swift` |
| constellation | — | the node-link map | `MapRenderer.swift` |

### Free word cloud (⌘4)

`WordCloudView.swift` is an alternate lens, not a camera mode. It replaces the
canvas while active; the 2D/3D engine stops, and switching back restores the
previous constellation and camera state.

#### Layout

`WordCloudLayout.make(graph:size:)` is deterministic and runs once per filter or
size change, never per frame.

1. Sort tags by weight (ties by label).
2. Map weight to type size with a blend of frequency and rank:

   ```
   blend = 0.68 × weightNorm + 0.32 × rankNorm
   size  = 10.5 + (maxFont − 10.5) × blend^0.82
   maxFont = clamp(10.5% of the shorter view side, 34 … 76)
   ```

   The rank term keeps a batch of equally-shared words from collapsing into one
   uniform size.
3. Place words on a slow elliptical spiral: `x = cos θ × t × width/2`,
   `y = sin θ × t × height/2`, with a per-word phase from `StableID.hash`.
   A word is accepted when its padded rect is inside the view and does not
   intersect an already-placed word.
4. If placement fails, retry at 0.88, 0.76, 0.64, and 0.54 of the font size.
   Words longer than the canvas are first shrunk to fit. Anything below 8.5 pt is
   dropped.

Colour encodes provenance: a tag shared by multiple providers is cyan (the bridge
accent), a single-provider tag uses that provider’s colour, and a tag with no
resolved neighbours falls back to the topic palette.

#### Rendering and interaction

`WordCloudRenderer` draws three faint orbit rings, a tick ring, and a radial
accent field, then the words centred on their layout rects. Selection and hover
add a coloured glow and underline; every other word dims to 18%. An optional
15 fps `TimelineView` adds a ±1.4 pt vertical drift when **MOTION** is on.

Hit testing is rect containment on the cached layout, preferring the smallest
rect under the pointer. Clicking a word selects its tag node, which opens the
same tag inspector and isolates exactly the same thread set as clicking the
diamond on the map. Clicking empty space deselects.

### Hybrid cloud (⌘5)

The hybrid lens runs inside `GraphCanvasView`, so it keeps the full camera,
gestures, 2D/3D crossfade, minimap, and hit testing. `MapRenderer` draws the
constellation skeleton at full strength but suppresses tag diamonds and tag
labels; the keyword words themselves become the tag representation. A dark
plate behind each word keeps it readable over the edges.

#### Layout

`HybridLayoutCache.layout(graph:graphRevision:projection:size:positionEpoch:)`
resolves words against the live `MapProjection`, so they follow the force
simulation, panning, zoom, and 3D orbit. Work is split into three cached stages
so only stage 3 runs when the camera moves:

1. **Seeds (per graph).** Tags are sorted by weight as in the free cloud, and
   each seed keeps its extracted label, provider palette, colour, rank, and
   phase. Graph rebuilds bump `AppModel.graphRevision`, the only condition that
   invalidates this stage.
2. **Text metrics (per canvas size).** The smaller type ramp
   `maxFont = clamp(5.2% of the shorter view side, 20 … 38)` is rendered into
   five font steps (`1.0, 0.88, 0.76, 0.64, 0.54`), measured once per seed, and
   reused for every pan and zoom.
3. **Placement (per projection change).** Each tag node is projected through
   `MapProjection`; the projected point is the word's **anchor**, so it inherits
   the tag's structural position between the conversations that share it.
   Try the anchor first; on collision, search a circular spiral outward to at
   most 30% of the shorter view side, trying smaller font steps as needed. Keep
   the word rect inside the canvas; skip anchors far off-screen.

Placement is memoized on `(graphRevision, canvas size, projection size, 2D
camera, 3D camera, mode blend, position epoch)`. `GraphEngine.positionEpoch`
advances only when positions actually change, so a settled camera reuses the
previous layout and pays just a key comparison.

Collision tests go through a 64 pt spatial hash instead of scanning every placed
word, which keeps the pass cheap even while the whole constellation is settling.

If collision resolution displaced a word by more than 9 pt, a dashed tether is
drawn from the anchor to the word plus a dot at the tag position.

This is the key difference from the free cloud: size still encodes shared
conversation count, but position encodes graph structure instead of a neutral
spiral.

#### Rendering and interaction

`HybridWordRenderer` uses the same sizing, colours, glow, underline, and
deselection behaviour as the free cloud, plus a dark backing plate and text
shadow for contrast against the full-strength map. Focus follows the map's
`focusPath`, so selecting a thread keeps its tags bright while unrelated words
dim.

Hover and click hit testing checks the hybrid word rects first, then falls back
to the engine's normal node hit test. Clicking a word selects its tag node and
opens the normal tag inspector.

---

## 10. Interaction

Implemented in `GraphCanvasView.swift` (gestures/overlays) and `GraphEngine`
(navigation/hit testing).

| Input | Result |
| --- | --- |
| Drag (2D) | pan; target follows the drag directly, no easing lag |
| Drag (3D) | orbit (yaw/pitch, sensitivity 0.006 rad/px) |
| Shift-drag (3D) | pan the camera target across the view plane |
| Pinch / +− | 2D zoom about the pointer, or 3D distance change |
| Click | hit test → select node (or deselect on empty space) |
| Hover | hit test → highlight path + hover card + pointing-hand cursor |
| ⌘0 / fit control | frame all nodes |
| ⌘3 / 2D–3D control | crossfade modes |
| ⌘4 / CLOUD control | switch to the free word cloud |
| ⌘5 / HYBRID control | switch to the constellation-anchored word cloud |
| ⌘6 / PHILOSOPHY button | isolate formal philosophy and group its subfields |
| Click a word (free cloud) | select its tag node and isolate its threads |
| Click a word (hybrid) | select its tag node; falls back to normal node hit testing |
| Type in search | highlight matching threads and their hub/tag paths in place |
| Return in search | isolate the map to matching threads; SHOW ALL restores the full map |
| ⌘F | focus search |
| Esc | deselect / close inspector |

Hit testing iterates nodes, projects each, and accepts the nearest within
`hitRadius + 6` (root 46, group 32, thread 8, tag 8), scaled by depth in 3D.
Ties prefer the nearer depth. Drags of 4 pt or less count as clicks.

---

## 11. Performance model

The engine ticks at 60 Hz but publishes frames adaptively:

| State | Publish rate |
| --- | --- |
| simulation settling, camera moving, mode blending, interacting | 45 fps |
| ambient motion on, app active | 10 fps |
| ambient motion on, app inactive | 2 fps |
| ambient motion off and nothing moving | event-driven only |

The free word cloud is outside the engine loop: its layout is cached, and only
the optional drift redraws at 15 fps (static when **MOTION** is off). The hybrid
cloud shares the map's camera throttle and only re-places words when the
projection changes; its seeds and text metrics are cached per graph and canvas
size, collision tests use a spatial hash, and hover/click hit testing reuses the
same layout object as the renderer instead of rebuilding it.

`MapRenderer` is a per-frame object. It projects each node once into a small
cache that the edge, node, label, and aura passes share, and the focus path is
resolved once per frame rather than per edge (previously each `isHighlighted`
call re-walked the graph).

Other guards:

- `GraphFilters.maxThreads = 420` caps rendered conversations
- simulation hard stop at 360 steps
- 3D layout computed once per graph, not per frame
- glow layers only drawn when a path is focused
- pulse budget caps animated dots
- canvas publishes a single `RenderFrame` per tick, so SwiftUI invalidates once

Turning **MOTION** off in the sidebar (or *Map → Ambient Motion*) gives an
essentially static map with near-zero idle CPU.

---

## 12. Testing and determinism

`make test` runs the core suite (`Core/Tests/MindMapCoreTests/`); `make test-app`
runs the hostless app-logic suite (`Tests/App/`). Relevant to the visualization:

- `testAnchorsAndSimulationRemainFinite` — no NaN/∞ after relaxation
- `testSpatialLayoutIsFiniteAndDeterministic` — 3D anchors are finite and stable
- `testLayoutIsDeterministic` — same graph → same anchors
- `testTopicGroupingProducesClusters`
- `testTagGraph`, `testFocusPath`
- `testKeywordsFavorTitleAndTopics`, `testStopwordsAndTokens`
- `testDomainsAreClassifiedAtRegionLevel`, `testSegmentsSplitWhenTopicShifts`
- `testRegionGroupingBuildsHierarchy`, `testDemoArchiveProducesRegionHierarchy`
- `testPipelineIsDeterministic`, `testCachedProfilesAreReused`
- `testSpendFollowsSegmentsAndRegions`, `testSessionCostRescalesTrimmedSegmentCosts`
- `testCameraBasisIsOrthonormal`, `testProjectionOfTargetIsCentered` (app)
- `testScreenAndWorldTransformsAreInverse`, `testSpatialModeOrbitZoomPanAndReset` (app)
- `testWordsFitTheCanvasAndDoNotOverlap`, `testWordsAreAnchoredInsideTheCanvasAndDoNotOverlap` (app)

Determinism is a design constraint, not an accident: `StableID.hash` replaces
`hashValue` (which is seeded per process) everywhere visual output depends on
hashes.

---

## 13. Extending the visualization

### Add a new grouping lens

1. Add a case to `GroupingMode` (`MindMapGraph.swift:5`).
2. Add a branch in `GraphBuilder.build` that produces `GroupSpec`s.
3. Add a sidebar control (`SidebarView.swift`) and, if useful, a HUD title in
   `GraphCanvasView.mapOverlays`.

No renderer changes are needed — groups are already generic hubs.

### Add a new node kind

Touch points: `NodeKind`, `GraphBuilder`, `HUD.color(for:)`,
`MapRenderer.drawNodeScaled` + a draw function, `GraphEngine.hitRadius`, and
`GraphLayout`/`GraphLayout3D` radii. Labels are generic and need no change.

### Extend the cloud modes

`WordCloudLayout.make` owns free-cloud placement and sizing; `WordCloudRenderer`
owns its passes. `HybridLayoutCache` owns graph seeds, text metrics, and
anchor-relative placement, while `HybridWordRenderer` owns the hybrid passes and
tethers. Add colour or typography rules in those types. New data sources should
continue to arrive as `tagNodes`, so the map and both cloud lenses stay in sync.

---

## 14. Known limitations

- Rendering caps at 420 conversations; use source/time/search filters for larger
  archives.
- Keyword extraction is TF-IDF-ish and English/German only. Mixed-language or
  non-Latin archives will produce weaker tags.
- Topic clusters are single-assignment: a thread belongs to one hub even if it
  spans several topics. Tag edges still connect it to the others.
- 3D layout is static (no relaxation), so very dense clouds can overlap; the
  depth sort and label occlusion keep it readable rather than physically
  collision-free.
- Labels are truncated (22 chars for tags, 30–38 for threads) and dropped when
  they collide; zoom in to recover them.
- The cloud lenses only show where shared keywords exist, and only tags that pass
  the map’s tag budget (§4) — not every word in the archive. Use the topic lens
  or search to narrow a large vocabulary.
- The hybrid cloud keeps words legible by pushing them away from their anchors;
  in dense maps the dashed tethers can be long, and a few low-weight words may
  be dropped when no collision-free spot is found.
