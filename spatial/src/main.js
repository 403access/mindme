import './style.css';
import { App } from './app.js';
import { DomHud } from './ui/domHud.js';
import { View } from './view.js';
import { XRSystem } from './xr.js';

// Development-only WebXR simulator. ?xr-sim injects Meta's Immersive Web
// Emulation Runtime, so the full immersive path can be exercised in a desktop
// Chromium (or a VM) without a headset. Production builds drop this block.
const params = new URLSearchParams(location.search);
const onQuestBrowser = /OculusBrowser|Quest/i.test(navigator.userAgent);
if (import.meta.env.DEV && params.has('xr-sim') && !onQuestBrowser) {
  try {
    const { XRDevice, metaQuest3 } = await import('iwer');
    const { DevUI } = await import('@iwer/devui');
    const device = new XRDevice(metaQuest3);
    device.installRuntime({ forceInstall: true });
    device.installDevUI(DevUI);
    device.stereoEnabled = false;
    window.__mindmeXRDevice = device;
    console.info('[mindme] XR simulator active — use the DevUI panel to move the headset and controllers.');
  } catch (error) {
    console.error('[mindme] could not start the XR simulator', error);
  }
}

const canvas = document.getElementById('stage');
const app = new App();
const view = new View({ canvas, app });
const xr = new XRSystem({ renderer: view.renderer, view, app });
const hud = new DomHud(app);

app.attach({ view, hud, xr });
window.__mindme = { app, view, xr, hud };

// Offline after the first visit. Register before the awaited library load so
// the registration cannot miss the page's load event.
if ('serviceWorker' in navigator && import.meta.env.PROD) {
  navigator.serviceWorker.register('./sw.js').catch((error) => {
    console.warn('[mindme] offline cache unavailable', error);
  });
}

try {
  await app.start();
} catch (error) {
  console.error('[mindme] startup failed', error);
  app.toast(`Could not start MINDME: ${error.message}`, 'error');
}

hud.init();

// The XR pose is only valid after the renderer submits a frame, so the loop
// renders first and resolves locomotion/hover against the fresh matrices.
let last = performance.now();
view.renderer.setAnimationLoop((time) => {
  const now = time ?? performance.now();
  const dt = Math.min(0.1, Math.max(0, (now - last) / 1000));
  last = now;

  view.update(dt);
  xr.update(dt);
  view.render();
});
