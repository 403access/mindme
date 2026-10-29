---
title: Development
description: Build, test, release, and understand the MINDME codebase.
---

# Development

## Requirements

- macOS 14 or newer for the desktop app
- iOS 17 or newer for the iPhone app
- Xcode 16+ (built and tested with Xcode 27 / Swift 6.4)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the
  Xcode project
- Node.js 22+ for this documentation site and the WebXR viewer in `spatial/`

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

## iPhone

```bash
cd MindMap
make ios          # generate project, build for iPhone Simulator
```

Or select the `MindMapIOS` scheme in Xcode and run on an iPhone simulator or device. The target
is iPhone-only for now; simulator builds need no signing team, device builds use automatic
signing. The mobile shell is `App/MobileRootView.swift`; `App/Platform.swift` holds the AppKit ↔
UIKit shims. Both apps link the same `MindMapCore` package.

To install directly on a connected iPhone:

```bash
cd MindMap
make ios-device DEVICE_ID=00008101-... TEAM_ID=ABCDE12345
```

`DEVICE_ID` comes from `xcrun devicectl list devices`; `TEAM_ID` from Xcode → Settings →
Accounts → your team.

Run the test suites (importers, keyword extraction, clustering, graph filters, layout, storage, cameras, word clouds):

```bash
make test          # core suite
make test-app      # app logic suite (cameras, graph engine, app model, cloud layouts)
make test-all      # both
```

## Meta Quest 3 (WebXR)

The headset build is a separate static app in `spatial/`:

```bash
cd spatial
npm install
npm run dev       # http://localhost:5173
npm run dev:sim   # simulated Quest 3 in desktop Chromium (?xr-sim)
npm run check     # data-layer checks in Node
npm run build     # spatial/dist
```

`dev:sim` uses Meta's Immersive Web Emulation Runtime (a dev dependency) to run the real
immersive session and controller input without a headset; it is stripped from production builds
and ignored on the Quest Browser user agent. Use it in desktop Chromium, including a VM with GPU
acceleration, to exercise the XR path before a hardware pass.

To try it on a Quest over USB, forward the dev server and open localhost in the headset browser:

```bash
adb reverse tcp:5173 tcp:5173
```

`localhost` is a secure context, so WebXR starts without HTTPS. For hosting, build with
`--base=/mindme/quest/`; the docs workflow copies the bundle into `website/build/quest` and
publishes it at [403access.github.io/mindme/quest](https://403access.github.io/mindme/quest/). See
[`spatial/README.md`](https://github.com/403access/mindme/blob/main/spatial/README.md) for the
module map, controls, and limits.

## Documentation site

This site is built with Docusaurus:

```bash
cd website
npm install
npm start         # local dev server
npm run build     # static site in website/build
npm run serve     # preview the production build
```

## Project layout

```
MindMap/
├── App/                     SwiftUI app (macOS + iPhone)
│   ├── MindMapApp.swift     app lifecycle, menus (macOS) / mobile entry (iOS)
│   ├── AppModel.swift       library, filters, import orchestration
│   ├── MobileRootView.swift iPhone shell: top bar, sheets, document pickers
│   ├── Platform.swift       AppKit/UIKit shims, export document, cursor + active state
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
    ├── Graph/               graph builder, 2D anchors/force layout, 3D anchors
    ├── Store/               local JSON persistence
    └── Demo/                deterministic demo archive
```

The core package is platform-neutral (Foundation plus its own `Vec2`/`Vec3`), so the macOS and
iPhone targets link it unchanged. The rendering layer is SwiftUI `Canvas`; the mobile shell adds
touch-first sheets and the Files import/export pickers around the same views.

```
spatial/                     WebXR viewer (three.js + Vite)
├── src/data/                library normalization, keywords, graph, 3D anchors
├── src/render/              instanced constellation and canvas labels
├── src/ui/                  world-space HUD panels and the flat DOM inspector
├── src/xr.js                WebXR session, controller/hand rays, locomotion
└── scripts/check.mjs        headless data-layer checks
```

## Reading the map

- **Root hexagon** — all currently visible threads.
- **Provider hub** — one per source; the count badge shows how many conversations it contains.
- **Conversation node** — size scales with message volume; colour follows the provider.
- **Diamond tag** — a keyword shared by at least two conversations. It links threads across
  providers.
- **Bright path** — the selected thread, its cluster, and its tags; everything else dims to
  keep context.
- **Word cloud (⌘4)** — the same filtered tag nodes as sized words in a free spiral layout.
  Larger type means more conversations share that keyword; click a word to isolate its threads.
- **Hybrid cloud (⌘5)** — the word cloud embedded in the constellation. Words start at their
  tag node's projected position and move only as far as needed to avoid collisions.

See [Visualization](./visualization.md) for the implementation details.

## Interaction

| Action | Result |
| --- | --- |
| Drag / pinch (2D) | Pan / zoom (trackpad magnify or the +/− controls) |
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
| **⌘4** | Toggle the free word cloud |
| **⌘5** | Toggle the hybrid cloud |
| **⌘R** | Reload the local library |
| **Esc** | Deselect / close the inspector |

## Performance notes

The 2D force simulation runs at 60 Hz only while settling (about six seconds), then the
renderer drops to a 10 fps ambient clock. The 3D layout is deterministic and static; orbiting
and projecting it is cheap, and the same throttle applies.

All node sizes and labels are drawn in screen space so zoom changes spacing but never
legibility, and the canvas only publishes a frame when something actually changed. Toggle
**MOTION** off in the sidebar (or *Map → Ambient Motion*) for an essentially static,
near-zero-idle-CPU map. The free word cloud packs its words once per filter/size change and
only runs a gentle 15 fps drift while it is visible. The hybrid cloud re-resolves word
collisions against the live projection each frame, keeping words tethered to the map.

## Privacy

There is no networking code in either app. Export files and the OpenCode database are parsed
locally and normalized into a JSON library in Application Support. On macOS, use *File → Reveal
Library in Finder* to inspect or delete it; on iPhone the library stays inside the app container
and **Copy library path** in Help shows its location.

## Limitations

- Gemini Takeout activity contains prompts but generally not model responses; those
  conversations appear as prompt-only threads.
- Gemini HTML exports are parsed best-effort; the JSON activity export is more reliable.
- ChatGPT branches: MINDME follows the currently selected branch, not abandoned
  regenerations.
- The map renders at most 420 conversations at once (configurable in
  `GraphFilters.maxThreads`); use filters for very large archives.
- Keyword extraction is intentionally lightweight (TF-IDF-ish, English + German stopwords).
  It is explainable and instant, not an embedding model.
- The Mac app is ad-hoc signed for local use. For distribution you will want your own Developer
  ID and notarization. The iPhone target uses automatic signing and needs a development team for
  device builds; simulator builds need no signing.

## Mobile notes

The iPhone target is intentionally phone-first: the map fills the screen, filters and the
inspector are sheets, and the top bar exposes import plus an overflow menu for reload, demo,
export, help, and reset. The system Files picker handles JSON, HTML, and SQLite inputs; the
export uses the share sheet.

- OpenCode's local database scan is Mac-only because iOS is sandboxed. Pick an `opencode.db`
  manually to import it on iPhone.
- The iPhone app uses the same `MindMapCore` parsers, topic pipeline, and renderers as the Mac
  app, so normalized libraries and Quest exports are interchangeable.
- iPad layout is not a target yet (`TARGETED_DEVICE_FAMILY = 1`); iPad runs the iPhone app in
  compatibility mode.
