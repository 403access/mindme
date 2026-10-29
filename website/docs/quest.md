---
title: Meta Quest 3
description: Run MINDME as a WebXR constellation in the Meta Quest Browser.
---

# Meta Quest 3

MINDME ships a **WebXR** build for the Meta Quest 3. It is a static web app in
[`spatial/`](https://github.com/403access/mindme/tree/main/spatial) that opens in the Quest
Browser and enters an immersive session. It reads the same library export as the macOS app and
renders the constellation in room-scale space, with world-space control panels and an inspector.

The macOS app is unchanged and remains the place to import and analyze conversations. The
headset build is a viewer for a normalized library: export it, load it, and walk around it.

## Quick start

### 1. Export from the Mac

In the macOS app, choose **File → Export Library for Quest…** (⌘E). You get a
`mindme-library.json` containing every thread, message, tag-ready text, and any OpenCode cost
and token data. Nothing is uploaded.

### 2. Get the app into the headset

**Option A — local dev over USB (nothing published).** WebXR needs a secure context;
`http://localhost` qualifies, so tunnel your Mac's dev server to the headset:

```bash
cd spatial && npm install && npm run dev
adb reverse tcp:5173 tcp:5173
```

Open **`http://localhost:5173`** in the Meta Quest Browser. Keep the dev server running.

**Option B — hosted HTTPS.** The documentation workflow publishes the build at
**https://403access.github.io/mindme/quest/** on every push under `spatial/`. To serve it
yourself:

```bash
cd spatial
npm run build -- --base=/mindme/quest/
# serve spatial/dist over HTTPS
```

### 3. Get the file to the headset

The export lives on the Mac, so choose one of:

- **Serve it from the dev server (recommended for USB).** Copy the export into
  `spatial/public/library.json` and open `http://localhost:5173/?library=./library.json` in the
  headset. The file is read from your Mac over the ADB tunnel and never uploaded. Keep it out
  of published builds (it is git-ignored).
- **`adb push`** the file to `/sdcard/Download/`, then press **LOAD JSON** in the headset and
  pick it.
- **Cloud storage** or any reachable URL, using **LOAD JSON** or `?library=<url>`.

### 4. Load and enter

On the flat page, press **LOAD JSON** (unless you used `?library=`) and pick the file, then
**ENTER VR**. The library is parsed in the headset and stored in the browser's IndexedDB, so the
next visit restores it. **HELP → CLEAR STORED LIBRARY** removes it. A production build registers a small
service worker, so after the first visit the app itself opens offline; only the library storage
and WebXR session are needed.

The app also ships a demo archive: seven of its conversations are relabelled as OpenCode and
given synthetic token and spend data, so the COST overlay can be explored without importing
anything.

## What you can do in the headset

- **Provider, topic, and era constellations** — the same deterministic graph and keyword tags
  as the desktop app. Topic clustering and tag selection use the shared algorithms.
- **Point and select** with a controller ray or a hand pinch. Hubs, conversations, and tags all
  respond; the selected path lights up and everything else dims.
- **Inspect in space** — the inspector opens beside the map with provider, model, dates,
  message count, tokens/spend, tags, and a paginated transcript. Group and tag inspectors list
  their member threads; touch a row to jump to that conversation.
- **Filter without leaving VR** — the control board toggles sources, time windows, groupings,
  tags, labels, ambient motion, and spend heat. **SHOW ALL** restores a filtered-out map.
- **Move naturally** — left stick walks, right stick snaps in 30° turns, right stick up/down
  scales the constellation, and **A / X** recenters the map and panels in front of you.
- **Comfort defaults** — teleport-free smooth locomotion at 1.35 m/s, snap turning instead of
  smooth yaw, and a static-but-alive constellation with a gentle sway you can disable.

## Flat preview

`npm run dev` also serves a complete flat version in a desktop browser: orbit with the mouse,
scroll to zoom, click nodes, and use the search box, provider chips, grouping, time windows, and
the HTML inspector. It is the fastest way to verify a library before putting on the headset.

## Test without a headset

A VM cannot emulate Horizon OS or the Quest Browser, but it can run the app's real immersive
WebXR path in desktop Chromium using Meta's
[Immersive Web Emulation Runtime](https://meta-quest.github.io/immersive-web-emulation-runtime/):

```bash
cd spatial
npm run dev:sim      # http://localhost:5173/?xr-sim
```

Press **ENTER VR**. The DevUI overlay simulates a Quest 3 headset and Touch controllers: drag
the controller gizmos to aim at the map, press the trigger in the side panel, move the headset,
and exercise the same renderer, rays, panels, and locomotion as the headset build.

The simulator is a **development-only** dependency. `?xr-sim` is disabled in production builds
and ignored on the Quest Browser user agent, so it cannot override native WebXR on a real
headset. It needs WebGL (enable GPU acceleration in a VM); it does not reproduce Horizon OS,
guardian, Quest performance, or compositor behaviour.

For the hosted build, use the
[Immersive Web Emulator](https://chromewebstore.google.com/detail/immersive-web-emulator/cgffilbpcibhmcfbgggfhfolhkfbhmik)
browser extension, which injects the same runtime into any page.

## Limits

The headset build deliberately does not include:

- **Region grouping**, which depends on the Swift topic pipeline, taxonomy file, and per-thread
  profile cache.
- **Word cloud and hybrid cloud lenses** and the 2D map.
- **Raw export import** (ChatGPT/Gemini/Claude/OpenCode source files). Import on the Mac first,
  then export the normalized library.
- **Topic reclassification** and taxonomy editing.

The visible-thread cap of 420 applies, and only OpenCode archives carry spend. Like the Mac
app, all rendering and parsing happens on device; the web app makes no analytics or telemetry
requests.

## Development

```bash
cd spatial
npm install
npm run dev       # http://localhost:5173
npm run check     # Node-side data checks
npm run build     # spatial/dist
```

See [`spatial/README.md`](https://github.com/403access/mindme/blob/main/spatial/README.md) for
the module map, deployment notes, and troubleshooting.
