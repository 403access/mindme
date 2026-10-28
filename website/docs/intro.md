---
title: MINDME
slug: /
description: A local-first constellation of the conversations you have with different AI assistants.
---

# MINDME

A futuristic, local-first mind map for the conversations you have with different AI
assistants. Import exports from **ChatGPT**, **Google Gemini**, and **Claude**, scan your
local **OpenCode** session library, or bring your own JSON — then explore everything as a
living constellation of sources, topics, and shared language.

The map is **not a word cloud**. It is a node-link force-directed graph: conversations keep
their identity, provider hubs group them, and shared keywords appear as small diamond tag
nodes that bridge otherwise separate clusters. Read [Visualization](./visualization.md) for
the full design.

![MINDME map](/img/map.jpg)

## What it does

- **Loads real conversations** — ChatGPT `conversations.json`, Google Takeout Gemini Apps
  activity, Claude `conversations.json`, HTML Takeout pages (best effort), the local OpenCode
  SQLite library, and a documented generic schema.
- **Groups the map** by provider, shared topic keyword, or time period.
- **Filters the signal** by source, time window, and free-text query, with a live thread index.
- **Connects conversations** through shared keyword tags, creating bridges across providers
  without merging the underlying threads.
- **Inspects everything** — select a node to read the transcript, see metadata, jump to the
  source in the browser, or click a tag to isolate every conversation behind it.
- **Feels alive** — an animated force-directed constellation with neon HUD panels, energy
  pulses along active paths, a minimap, and an animated camera.
- **2D or 3D** — flip the map into a spatial perspective with a z-axis, depth-sorted nodes, a
  perspective floor, and an orbit camera.
- **Stays on your Mac** — no network calls, no accounts, no telemetry. Data is normalized
  into `~/Library/Application Support/MindMap/library.json`.

A curated demo dataset is generated on first launch so the map is explorable before importing
anything. Demo threads are labelled and can be cleared with one click; the first real import
clears them automatically.

## Screenshots

![MINDME inspector](/img/inspector.jpg)

![MINDME 3D perspective](/img/spatial.jpg)

## Quick start

```bash
git clone https://github.com/403access/mindme.git
cd mindme/MindMap
make run          # generate project, build Debug, open the app
```

Requirements: macOS 14+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Explore the docs

- [Importing conversations](./importing.md) — supported formats, OpenCode, and the generic schema.
- [Visualization](./visualization.md) — graph model, keyword pipeline, layouts, renderer, and extension points.
- [Development](./development.md) — build, test, release, architecture, and performance notes.
