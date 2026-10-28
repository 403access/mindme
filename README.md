# MINDME

A futuristic, local-first mind map for the conversations you have with different AI assistants. Import exports from **ChatGPT**, **Google Gemini**, and **Claude**, scan your local **OpenCode** session library, or bring your own JSON — then explore everything as a living constellation of sources, topics, and shared language.

![MINDME map](website/static/img/map.jpg)

![MINDME inspector](website/static/img/inspector.jpg)

The same constellation in spatial mode:

![MINDME 3D perspective](website/static/img/spatial.jpg)

## What it does

- **Loads real conversations** — ChatGPT `conversations.json`, Google Takeout Gemini Apps activity, Claude `conversations.json`, HTML Takeout pages (best effort), the local OpenCode SQLite library, and a documented generic schema.
- **Groups the map** by provider, shared topic keyword, time period, or hierarchical **region**.
- **Classifies conversations and their parts** — each thread is segmented where the topic actually changes, then scored against an editable region spine (product, technology, legal, finance, design, research, operations, personal) with sub-regions underneath. A mixed project thread can be 60% technology and 40% legal; the inspector shows every segment.
- **Filters the signal** by source, time window, and free-text query, with a live thread index.
- **Connects conversations** through shared keyword tags, creating bridges across providers without merging the underlying threads.
- **Inspects everything** — select a node to read the transcript, see metadata, jump to the source in the browser, or click a tag to isolate every conversation behind it.
- **Feels alive** — an animated force-directed constellation with neon HUD panels, energy pulses along active paths, a minimap, and an animated camera.
- **2D or 3D** — flip the map into a spatial perspective with a z-axis, depth-sorted nodes, a perspective floor, and an orbit camera. Drag to orbit, Shift-drag to pan, pinch or use +/− to zoom.
- **Word cloud** — switch the same filtered library into a semantic cloud where keywords are sized by how many conversations share them. Click a word to isolate its threads. Toggle with **⌘4**, the **CLOUD** view control, or the sidebar.
- **Hybrid cloud** — keep the constellation's root, hubs, threads, and links while sizing and anchoring the words to their tag nodes. The map structure stays visible beneath the vocabulary. Toggle with **⌘5**, the **HYBRID** control, or the sidebar.
- **Stays on your Mac** — no network calls, no accounts, no telemetry. Data is normalized into `~/Library/Application Support/MindMap/library.json`.

A curated **demo dataset** is generated on first launch so the map is explorable before importing anything. Demo threads are labelled and can be cleared with one click; the first real import clears them automatically.

## Requirements

- macOS 14 or newer
- Xcode 16+ (built and tested with Xcode 27 / Swift 6.4)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the Xcode project

## Run it

```bash
cd MindMap
make run          # generate project, build Debug, open the app
```

Or open `MindMap/MindMap.xcodeproj` in Xcode and run the `MindMap` scheme.

Build a distributable app bundle:

```bash
make release      # -> MindMap/dist/MINDME.app
make install      # -> ~/Applications/MINDME.app
```

Run the core test suite (importers, keyword extraction, clustering, graph filters, layout):

```bash
make test
```

## Documentation site

The docs are a [Docusaurus](https://docusaurus.io) site in [`website/`](website). Run it locally:

```bash
cd website
npm install
npm start         # http://localhost:3000/mindme/
```

`npm run build` produces a static site in `website/build`. Pushing changes under `website/`
to `main` deploys it to GitHub Pages via [`.github/workflows/docs.yml`](.github/workflows/docs.yml);
enable **Settings → Pages → Source: GitHub Actions** once in the repository settings.

## Importing conversations

| Source | Where to get it | File to import |
| --- | --- | --- |
| ChatGPT | Settings → Data controls → Export data | `conversations.json` |
| Gemini | Google Takeout → My Activity → Gemini Apps | `My Activity.json` (or the Takeout folder) |
| Claude | Settings → Privacy → Export data | `conversations.json` |
| OpenCode | Already on this Mac | File → Import OpenCode Sessions (⌘⇧O), or drop `opencode.db` |
| Any tool | MINDME generic schema | a `.json` file with a `threads` array |

You can drag files or whole folders onto the window, or press **⌘I**. The importer groups Gemini activity prompts by their conversation URL (falling back to a per-day bucket), reconstructs ChatGPT's active branch from `current_node` → parents, and skips hidden/system nodes.

Small synthetic exports for every format live in [`MindMap/Samples`](MindMap/Samples) — drag one onto the app to try the importer without sharing your own data.

### OpenCode

OpenCode stores its history in `~/.local/share/opencode/opencode.db`. MINDME opens that database **read-only in place** (nothing is copied) and normalizes the **150 most recently active top-level sessions**, including human prompts and assistant text. Subagent sessions, reasoning traces, tool calls, patches, and snapshots are intentionally excluded. The import takes under a second for a typical library; import again with ⌘⇧O to merge newer sessions.

The importer reads the `session_v2` / `session_message` schema used by current OpenCode releases. The session limit is `OpenCodeImporter.defaultSessionLimit`, and per-thread message caps live alongside it in `Core/Sources/MindMapCore/Import/OpenCodeImporter.swift`.

The synthetic demo archive remains available at any time via **File → Load Demo Dataset**; importing real data clears it so the map shows only your conversations.

### Generic schema

```json
{
  "threads": [
    {
      "id": "conversation-123",
      "provider": "gemini",
      "title": "Designing a solar punk transit map",
      "createdAt": "2026-03-01T10:00:00Z",
      "model": "gemini-3-pro",
      "messages": [
        { "role": "user", "text": "How do I start?", "timestamp": "2026-03-01T10:00:00Z" },
        { "role": "assistant", "text": "Start from topology…" }
      ]
    }
  ]
}
```

`provider` accepts `chatgpt`, `gemini`, `claude`, `opencode`, or anything else (shown as *Other*). If `provider` is omitted, MINDME infers it from the filename when possible.

## Regions and sub-regions

Choose **REGION** in the Lens section (or *Map → Group By → Region*). The map becomes two levels deep:

- an inner hub per **region** — Product, Technology, Legal, Finance, Design, Research, Operations, Personal, Emerging
- a ring of **sub-region** hubs inside it — e.g. Technology splits into Software, Architecture, and AI
- conversations fan out from the sub-region they spend most of their words in

The pipeline runs entirely on-device:

1. **Segment** each thread into exchanges (prompt + reply) and cut where the vocabulary shifts, time gap grows, or the prompt contains an explicit cue ("now let's switch to the contract").
2. **Classify** each segment against the taxonomy, parents gating children, using deterministic hashed text embeddings plus a seed lexicon (English + German).
3. **Smooth** the sequence with Viterbi so a single stray paragraph cannot tear a region apart.
4. **Roll up** weighted by prompt length — assistant verbosity does not get to pick the topic. The result is a soft distribution: a thread can belong to several regions.
5. **Cache** profiles per thread content hash in `~/Library/Application Support/MindMap/topics.json`; importing new chats does not reclassify old ones.

The default taxonomy lives in `Core/Sources/MindMapCore/Analysis/Topics/TopicTaxonomy.swift` and is mirrored to `~/Library/Application Support/MindMap/taxonomy.json` on first run. Edit labels, descriptions, or seeds there and use *Map → Reclassify Topics* (⌘⇧T) — no rebuild required. Low-confidence material lands in **Emerging** instead of being forced into a wrong region.

## Reading the map

- **Root hexagon** — all currently visible threads.
- **Provider hub** — one per source; the count badge shows how many conversations it contains.
- **Conversation node** — size scales with message volume; colour follows the provider.
- **Diamond tag** — a keyword shared by at least two conversations. It links threads across providers.
- **Bright path** — the selected thread, its cluster, and its tags; everything else dims to keep context.

Interaction:

| Action | Result |
| --- | --- |
| Drag / pinch (2D) | Pan / zoom (trackpad magnify or the +/- controls) |
| **⌘3** or the **2D/3D** map control | Toggle the spatial perspective |
| **⌘4** or the **CLOUD** control | Switch to the free word cloud |
| **⌘5** or the **HYBRID** control | Show the word cloud inside the constellation structure |
| Drag (3D) | Orbit the camera around the root |
| **Shift**-drag (3D) | Pan the camera target across the scene |
| Pinch / +− (3D) | Move the camera closer or farther |
| Click a node | Highlight its path and open the inspector |
| Click a thread in the sidebar | Jump to its constellation and open the transcript |
| Click a tag chip in the inspector | Isolate every thread behind that tag |
| Click a word in the cloud | Isolate its threads and open the tag inspector |
| **⌘0** | Fit the whole map |
| **⌘F** | Focus the search field |
| **⌘I** | Import exports |
| **⌘3** | Toggle 3D perspective |
| **⌘4** | Toggle the free word cloud |
| **⌘5** | Toggle the hybrid cloud |
| **⌘R** | Reload the local library |
| **Esc** | Deselect / close the inspector |

## Architecture

> **Deep dive:** [website/docs/visualization.md](website/docs/visualization.md) documents the graph model, keyword pipeline, both layouts, cameras, renderer, and extension points. The default visualization is a node-link constellation — keywords become diamond tag nodes and topic hubs, not sized text. Two opt-in cloud lenses sit over the same filtered tag data: a free word cloud (⌘4) and a hybrid cloud (⌘5) anchored to the constellation.

```
MindMap/
├── App/                     SwiftUI app (macOS)
│   ├── MindMapApp.swift     app lifecycle, menus
│   ├── AppModel.swift       library, filters, import orchestration
│   ├── GraphEngine.swift    simulation clock, 2D/3D cameras, hit testing, render throttling
│   ├── Perspective.swift    perspective camera, projection, 3D fit
│   ├── MapRenderer.swift    Canvas renderer (2D/3D nodes, edges, labels, depth)
│   ├── WordCloudView.swift  free word-cloud layout, renderer, hover cards, empty state
│   ├── HybridWords.swift    constellation-anchored word layout and renderer
│   ├── GraphCanvasView.swift gestures, minimap, orbit gizmo, hover cards, empty state
│   ├── SidebarView.swift    filter matrix
│   ├── DetailPanelView.swift thread/cluster inspector
│   └── Theme.swift          HUD design system
└── Core/                    Swift package, UI-independent and testable
    ├── Models/              ConversationThread, ChatMessage, Provider, ThreadLibrary
    ├── Import/              format sniffing + ChatGPT/Gemini/Claude/OpenCode/generic parsers
    ├── Analysis/            keyword extraction + topic clustering
    │   └── Topics/           segmentation, taxonomy, classifier, smoothing
    ├── Graph/               graph builder, 2D anchors/force layout, 3D anchors
    ├── Store/               local JSON persistence
    └── Demo/                deterministic demo archive
```

**Performance notes:** the 2D force simulation runs at 60 Hz only while settling (about six seconds), then the renderer drops to a 10 fps ambient clock. The 3D layout is deterministic and static; orbiting and projecting it is cheap, and the same throttle applies. The free word cloud packs words once per filter/size change and only animates a gentle 15 fps drift while it is on screen. The hybrid cloud caches keyword seeds, colours, and measured text per graph and re-places words only when the projection changes; word collisions use a spatial grid, and a settled camera costs a single cache-key comparison per frame. Projections are shared across the map's edge/node/label passes, and focus paths are resolved once per frame instead of per edge. All node sizes and labels are drawn in screen space so zoom changes spacing but never legibility, and the canvas only publishes a frame when something actually changed. Toggle **MOTION** off in the sidebar (or *Map → Ambient Motion*) for an essentially static, near-zero-idle-CPU map.

**Privacy:** there is no networking code in the app. Export files and the OpenCode database are parsed locally and normalized into a JSON library in Application Support. Use *File → Reveal Library in Finder* to inspect or delete it.

## Limitations / notes

- Google Takeout's Gemini activity export contains prompts but generally **not** model responses; those conversations appear as prompt-only threads.
- OpenCode imports the 150 most recent top-level sessions. Very large coding sessions are trimmed to the first 10 + last 50 messages, and individual messages are capped at 5,000 characters so the library stays responsive.
- Gemini HTML exports are parsed best-effort; the JSON activity export is more reliable.
- ChatGPT branches: MINDME follows the currently selected branch (`current_node`), not abandoned regenerations.
- The map renders at most 420 conversations at once (configurable in `GraphFilters.maxThreads`); use source/time/search filters for very large archives.
- Keyword extraction is intentionally lightweight (TF-IDF-ish, English + German stopwords). Topic classification uses deterministic hashed bag-of-words embeddings plus seed vocabularies — explainable and offline, not a neural sentence encoder. The `TopicEmbeddingProvider` protocol is the seam for dropping in a bundled CoreML MiniLM later.
- Topic analysis runs once per archive change and caches every thread profile by content hash. A 400-thread library takes a couple of seconds on first run; later launches reuse `topics.json`, and only new or edited conversations are reclassified.
- The app is ad-hoc signed for local use. For distribution you will want your own Developer ID and notarization.

## iOS

`MindMapCore` is already platform-neutral (Foundation + its own `Vec2`, iOS 17 minimum). The rendering layer is SwiftUI `Canvas`, so an iOS target mainly needs a compact sidebar/inspector presentation and touch gestures (the `MagnifyGesture` and tap handling already work on iOS 17). The project is structured so the core can be linked unchanged from a future iOS app target.
