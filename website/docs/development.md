---
title: Development
description: Build, test, release, and understand the MINDME codebase.
---

# Development

## Requirements

- macOS 14 or newer
- Xcode 16+ (built and tested with Xcode 27 / Swift 6.4)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the
  Xcode project
- Node.js 20+ only for this documentation site

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
├── App/                     SwiftUI app (macOS)
│   ├── MindMapApp.swift     app lifecycle, menus
│   ├── AppModel.swift       library, filters, import orchestration
│   ├── GraphEngine.swift    simulation clock, 2D/3D cameras, hit testing, render throttling
│   ├── Perspective.swift    perspective camera, projection, 3D fit
│   ├── MapRenderer.swift    Canvas renderer (2D/3D nodes, edges, labels, depth)
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

The core package is platform-neutral (Foundation plus its own `Vec2`/`Vec3`), so it can be
linked unchanged from a future iOS target. The rendering layer is SwiftUI `Canvas`.

## Reading the map

- **Root hexagon** — all currently visible threads.
- **Provider hub** — one per source; the count badge shows how many conversations it contains.
- **Conversation node** — size scales with message volume; colour follows the provider.
- **Diamond tag** — a keyword shared by at least two conversations. It links threads across
  providers.
- **Bright path** — the selected thread, its cluster, and its tags; everything else dims to
  keep context.

See [Visualization](./visualization.md) for the implementation details.

## Interaction

| Action | Result |
| --- | --- |
| Drag / pinch (2D) | Pan / zoom (trackpad magnify or the +/− controls) |
| **⌘3** or the **2D/3D** map control | Toggle the spatial perspective |
| Drag (3D) | Orbit the camera around the root |
| **Shift**-drag (3D) | Pan the camera target across the scene |
| Pinch / +− (3D) | Move the camera closer or farther |
| Click a node | Highlight its path and open the inspector |
| Click a thread in the sidebar | Jump to its constellation and open the transcript |
| Click a tag chip in the inspector | Isolate every thread behind that tag |
| **⌘0** | Fit the whole map |
| **⌘F** | Focus the search field |
| **⌘I** | Import exports |
| **⌘R** | Reload the local library |
| **Esc** | Deselect / close the inspector |

## Performance notes

The 2D force simulation runs at 60 Hz only while settling (about six seconds), then the
renderer drops to a 10 fps ambient clock. The 3D layout is deterministic and static; orbiting
and projecting it is cheap, and the same throttle applies.

All node sizes and labels are drawn in screen space so zoom changes spacing but never
legibility, and the canvas only publishes a frame when something actually changed. Toggle
**MOTION** off in the sidebar (or *Map → Ambient Motion*) for an essentially static,
near-zero-idle-CPU map.

## Privacy

There is no networking code in the app. Export files and the OpenCode database are parsed
locally and normalized into a JSON library in Application Support. Use *File → Reveal Library
in Finder* to inspect or delete it.

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
- The app is ad-hoc signed for local use. For distribution you will want your own Developer ID
  and notarization.

## iOS

`MindMapCore` is already platform-neutral (Foundation + its own `Vec2`, iOS 17 minimum). The
rendering layer is SwiftUI `Canvas`, so an iOS target mainly needs a compact sidebar/inspector
presentation and touch gestures (the `MagnifyGesture` and tap handling already work on iOS 17).
The project is structured so the core can be linked unchanged from a future iOS app target.
