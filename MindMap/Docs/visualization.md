# MINDME Visualization

How a library of imported conversations becomes the map you see. This is the
deep-dive companion to the [README](../../README.md): the graph model, the
keyword pipeline, both layouts, the camera/projection stack, and the renderer.

**It is not a word cloud.** Words never drive type size. Keywords become
topology — small diamond *tag nodes* and, in topic mode, group hubs — while the
main visual object is a node-link force-directed graph.

```
KeywordExtractor ──► tag nodes, topic hubs, inspector chips
                  └► (no sized text, no word-frequency layout)
```

---

## 1. Pipeline at a glance

```
ThreadLibrary
   │  GraphFilters (providers, since, search, maxThreads)
   ▼
GraphBuilder.build(library:filters:)        Core/Sources/MindMapCore/Graph/GraphBuilder.swift
   │  + KeywordExtractor.buildIndex
   │  + TopicClusterer (topic mode only)
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
| `group` | `group:provider:*`, `group:topic:misc`, `group:era:*`, `topic:*` | ring hub, radius 23 pt | fixed radius, halo on select | provider colour or topic palette |
| `thread` | `thread:<threadID>` | circle | `2.9 + min(3.6, weight × 0.95)` pt | provider colour |
| `tag` | `tag:<slug>` | diamond | `2.4 + min(2.2, weight × 0.35)` pt | fixed blue-grey |

Weights:

- thread `weight = 1 + min(3, log(1 + messageCount) × 0.55)`
- tag `weight = number of conversations using the keyword`
- group `weight = number of threads in the group`

### Edges

| Kind | Connects | Rest length | Spring strength | Render |
| --- | --- | --- | --- | --- |
| `rootGroup` | root → group | 300 | 0.28 | straight, provider tint |
| `groupThread` | group → thread | 118 | 0.52 | gently curved |
| `threadTag` | thread → tag | 72 | 0.34 | dashed `[1.5, 4.5]` |

Only `threadTag` edges cross group boundaries. That is the mechanism behind
"shared language bridges providers" — conversations are never merged, they are
linked through tag nodes.

### Focus path

`MindMapGraph.focusPath(for:)` returns the highlighted node set for the
selected or hovered node:

- **root** → everything
- **group** → itself, its threads, their tags, root
- **thread** → itself, its group, its tags, root
- **tag** → itself, all threads carrying it, their groups, root

`MapRenderer` draws anything outside that set at low opacity (`isDimmed`), which
is what makes the selected constellation pop.

---

## 3. Grouping modes

`GraphBuilder` (`GraphBuilder.swift:36`) supports three ways to cut the same
library into hubs. The mode only changes group membership, not the node set.

| Mode | Hubs | Notes |
| --- | --- | --- |
| `provider` | one per `Provider` enum case present | hub colour = provider colour |
| `topic` | up to `min(14, max(6, 6 + n/24))` keyword clusters + `MISCELLANY` | see below |
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
| thread | selected/hovered, or zoom ≥ 0.98 if in focus path, or zoom ≥ 1.35 | selected/hovered only |
| tag | selected, or zoom ≥ 1.7 and weight ≥ 4 | selected only |
| group | always, drawn toward the root | always |

Placement is greedy: candidates are sorted by priority (selected 1000, hovered
900, top-6 threads by weight 44, otherwise 10 + weight), then a label is skipped
if its rect intersects an already-placed rect. Backgrounds are filled at
55–82% opacity so labels survive over edges.

### Highlight vs. dim

`focusID = selectedNodeID ?? hoveredNodeID`. The focus path is recomputed per
frame from `graph.focusPath(for:)`; everything else is dimmed rather than
removed, preserving spatial context.

---

## 9. Interaction

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
| ⌘F | focus search |
| Esc | deselect / close inspector |

Hit testing iterates nodes, projects each, and accepts the nearest within
`hitRadius + 6` (root 46, group 32, thread 8, tag 8), scaled by depth in 3D.
Ties prefer the nearer depth. Drags of 4 pt or less count as clicks.

---

## 10. Performance model

The engine ticks at 60 Hz but publishes frames adaptively:

| State | Publish rate |
| --- | --- |
| simulation settling, camera moving, mode blending, interacting | 45 fps |
| ambient motion on, app active | 10 fps |
| ambient motion on, app inactive | 2 fps |
| ambient motion off and nothing moving | event-driven only |

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

## 11. Testing and determinism

`make test` runs 22 core tests (`Core/Tests/MindMapCoreTests/`). Relevant to the
visualization:

- `testAnchorsAndSimulationRemainFinite` — no NaN/∞ after relaxation
- `testSpatialLayoutIsFiniteAndDeterministic` — 3D anchors are finite and stable
- `testLayoutIsDeterministic` — same graph → same anchors
- `testTopicGroupingProducesClusters`
- `testTagGraph`, `testFocusPath`
- `testKeywordsFavorTitleAndTopics`, `testStopwordsAndTokens`

Determinism is a design constraint, not an accident: `StableID.hash` replaces
`hashValue` (which is seeded per process) everywhere visual output depends on
hashes.

---

## 12. Extending the visualization

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

### Adding a word-cloud mode

The data is already available: `MindMapGraph.tagNodes` carries a `weight` equal
to the number of conversations sharing each keyword. A cloud mode would be a
third `modeBlend` target alongside 2D/3D:

1. Lay out tag labels with a spiral or force placement keyed on `weight`.
2. Scale font size from `weight` (the one place word frequency would drive
   type, by design).
3. Render in a new pass in `MapRenderer`, skipping edges/nodes or dimming them.
4. Gate it behind a `MapMode` enum in `GraphEngine` so 2D, 3D, and CLOUD share
   the same `RenderFrame` plumbing.

This is intentionally not implemented: the map’s job is to preserve
conversation identity and provenance, which a word cloud discards.

---

## 13. Known limitations

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
