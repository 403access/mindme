# MINDME Spatial

MINDME for **Meta Quest 3**. This is a WebXR build of the constellation: the same library,
graph model, keyword tags, inspectable transcripts, and spend overlay as the macOS app,
rendered in the headset's room-scale space.

It is a separate, static web app — the SwiftUI app is untouched. Open it in the
**Meta Quest Browser**, load an exported `library.json`, and press **ENTER VR**.

```
spatial/
├── index.html               flat browser shell (launch card, filters, inspector, guide)
├── src/
│   ├── main.js              bootstrap and animation loop
│   ├── app.js               library/filter/selection state
│   ├── view.js              renderer, orbit preview, floor, recenter
│   ├── xr.js                WebXR session, controller/hand rays, locomotion
│   ├── storage.js           IndexedDB persistence (headset-local)
│   ├── data/                library normalization, keywords, graph, 3D layout
│   ├── render/              instanced constellation + canvas-texture labels
│   └── ui/                  world-space panels and the flat DOM HUD
├── scripts/check.mjs        headless data-layer checks
└── public/                  favicon and static assets
```

## Requirements

- Node.js 22+ for building and previewing
- A Chromium browser for the desktop/VM simulator
- A Meta Quest 3 (or Quest 2 / Pro) with **Developer Mode** for the USB workflow
- Optional: Android platform tools (`adb`) for `adb reverse` — any HTTPS static host works too

## Run it

### Desktop preview

```bash
cd spatial
npm install
npm run dev          # http://localhost:5173
```

The flat preview is the same app: orbit with the mouse, scroll to zoom, click a node, and use
the filter bar. WebXR is unavailable in a normal desktop browser, so the VR button is disabled.

### Test the XR path without a headset (VM-friendly)

A VM cannot emulate Horizon OS or the Quest Browser, but it can run the app's **actual immersive
WebXR path** in desktop Chromium. The build ships Meta's
[Immersive Web Emulation Runtime](https://meta-quest.github.io/immersive-web-emulation-runtime/)
as a development-only dependency:

```bash
cd spatial
npm run dev:sim      # opens http://localhost:5173/?xr-sim
```

Press **ENTER VR**. The DevUI overlay puts a simulated Quest 3 headset and Touch controllers in
the room: drag the controller gizmos to aim, use the trigger/thumbstick controls in the side
panels, or move the headset to look around. This exercises the real three.js WebXR session,
controller rays, panel hit-testing, locomotion, and input events — the same code the headset
runs.

Notes:

- `?xr-sim` is gated to development builds and is ignored on the Quest Browser user agent, so it
  can never override native WebXR on a real headset. Production bundles do not contain IWER.
- The simulator needs WebGL. In a VM, enable GPU acceleration or expect software rendering to be
  slow; use a browser window rather than a tiny remote viewport.
- It emulates the WebXR runtime and input, not Horizon OS, the Quest Browser, guardian, headset
  performance, or compositor behaviour. Do a hardware pass before shipping.

For the **hosted production build**, use Meta's
[Immersive Web Emulator](https://chromewebstore.google.com/detail/immersive-web-emulator/cgffilbpcibhmcfbgggfhfolhkfbhmik)
browser extension instead; it injects the same runtime into any page.

### On the headset (USB, no hosting)

WebXR requires a secure context. `http://localhost` counts, and `adb reverse` lets the
headset reach your Mac's dev server on its own localhost:

```bash
adb devices                      # confirm the Quest is authorized
adb reverse tcp:5173 tcp:5173
cd spatial && npm run dev
```

Then open **`http://localhost:5173`** in the Meta Quest Browser. Press **ENTER VR**. This
keeps the library and the dev server entirely on your machine and LAN — nothing is published.

The Vite dev server must stay running while you use the headset, and HMR is active, so edits
on the Mac appear in the headset.

### On the headset (hosted)

Build a static bundle and put it behind HTTPS:

```bash
cd spatial
npm run build                       # -> spatial/dist
npm run build -- --base=/mindme/quest/   # for a GitHub Pages project subpath
```

The docs workflow already does this: pushes under `spatial/` are built with
`--base=/mindme/quest/` and copied to `website/build/quest`, so the public URL is
**https://403access.github.io/mindme/quest/**.

Any static host works (Pages, Netlify, S3, a local HTTPS server). WebXR will not start on
plain `http://` except for `localhost`.

## Loading your library

1. In the macOS app: **File → Export Library for Quest…** (⌘E). This writes a
   `mindme-library.json` with the current library, including OpenCode cost and token data.
2. Get that file onto the headset. Three ways, in order of convenience:

   **Serve it locally (no transfer, recommended for the USB workflow).** Put the export
   beside the app and open it through the URL loader:

   ```bash
   cp ~/Desktop/mindme-library.json spatial/public/library.json
   # then open http://localhost:5173/?library=./library.json in the Quest Browser
   ```

   The dev server serves `public/` at the site root, so the headset reads the file from your
   Mac over the ADB tunnel. It never leaves your machine, and nothing is uploaded. Keep
   `library.json` out of builds/commits (it is git-ignored); if you copy it into `public/`
   and run `npm run build`, it would be baked into `dist/`, so remove it before publishing.

   **ADB push (hosted app).**

   ```bash
   adb push ~/Desktop/mindme-library.json /sdcard/Download/
   ```

   Then press **LOAD JSON** in the headset and pick it from Downloads.

   **Cloud storage.** Any file the Quest Browser can reach (Drive, Dropbox, email, a private
   URL) works with **LOAD JSON**, or serve it with `?library=<url>`.

3. Press **ENTER VR**.

The parsed library is stored in this browser's IndexedDB so the next visit starts where you
left off, and a small service worker caches the production bundle after the first load so the
app opens offline. **HELP → CLEAR STORED LIBRARY** removes it and restores the demo archive. The file
is read on-device; the app has no server, accounts, or telemetry. (Serving the app itself is a
normal web request; your conversations are never uploaded.)

Two URL parameters help with automated/local setups:

| Parameter | Effect |
| --- | --- |
| `?library=/path/library.json` | Fetch and load a library file next to the app |
| `?demo=1` | Ignore stored data and use the bundled demo |

The bundled demo mirrors the deterministic macOS archive. Seven of its conversations are
relabelled as **OpenCode** and given synthetic token counts and spend, so the COST overlay is
explorable out of the box. Its timeline is shifted to the present on load so the time windows
stay meaningful. To rebuild the asset from a Mac demo export:

```bash
node scripts/prepare-demo.mjs path/to/mindme-demo-library.json
```

## Controls

| Action | Headset | Desktop |
| --- | --- | --- |
| Select a node or button | Point + trigger, or pinch | Click |
| Focus / open inspector | Select a conversation, hub, or tag | Click a node |
| Page the transcript | **PREV / NEXT** in the inspector | Scroll the inspector |
| Isolate a tag | Select the tag chip in the inspector | Click a tag chip |
| Clear focus | **CLEAR FOCUS** / **SHOW ALL** | Esc |
| Walk | Left thumbstick | Drag to orbit (preview) |
| Snap turn 30° | Right thumbstick left/right | — |
| Scale the constellation | Right thumbstick up/down | Scroll |
| Recenter map + panels | **A / X** | — |
| Fit the map | **FIT MAP** | F |
| Show the guide | **GUIDE** | HELP |

Head tracking is always on. Hand tracking is requested as an optional feature; pinch dispatches
the same selection as a controller trigger. Controllers are the primary input. The first
immersive session opens the field guide automatically; dismiss it with **RETURN TO THE MAP**.

## Lenses and filters

- **PROVIDER**, **TOPIC**, and **ERA** groupings (topic clusters use the same deterministic
  keyword logic as the macOS app).
- Provider toggles, time windows (all / 12 months / 90 days / 30 days), and live search on the
  flat page.
- Tags, labels, motion, and **COST** spend heat (only for libraries with provider-reported cost).
- Selecting a node lights its path, dims the rest, and opens a transcript or member list.
- The demo and every imported library cap at 420 visible conversations, like the Mac app.

**Not in this build:** the region taxonomy lens (it needs the Swift topic pipeline and cached
taxonomy), the free/hybrid word-cloud lenses, raw ChatGPT/Gemini/Claude import, and topic
reclassification. Export from the macOS app after importing and analyzing there.

## Performance notes

The constellation is drawn with instanced meshes: one draw call for every conversation, one
for every tag, a handful of hub meshes, and three edge batches. The demo is ~70 draw calls and
~10k triangles. Labels are canvas textures scaled to a constant angular size, and a screen-space
declutter pass hides labels that would overlap a stronger one. Panels redraw only when their
content or hover state changes. Everything is deterministic and unlit, so the headset spends
its frame budget on resolution rather than lighting.

## Testing

```bash
npm run check     # data layer: normalization, grouping, search, focus, layout
npm run dev:sim   # simulated Quest 3 in desktop Chromium (?xr-sim)
npm run build     # production bundle
```

The checks run in Node against the same modules the app uses (no browser or headset needed).

## Troubleshooting

- **ENTER VR is disabled** — the page is not in a secure context, or the browser lacks
  `immersive-vr`. Use `localhost` via `adb reverse`, an HTTPS host, and the Quest Browser.
- **The headset cannot reach the dev server** — re-run `adb reverse tcp:5173 tcp:5173`; the
  reverse mapping disappears when the headset disconnects or reboots.
- **No controller ray** — move the controller; rays appear on the `connected` event. Check that
  the headset has controller tracking, not just hand tracking.
- **The file picker opens but the library does not load** — MINDME expects the normalized
  library JSON (`{ "threads": [...] }`), not a raw ChatGPT/Claude export. Use the macOS
  exporter.
- **Cost is empty** — only OpenCode archives carry provider-reported spend.
