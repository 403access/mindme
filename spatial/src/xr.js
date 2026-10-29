// WebXR session, controller/hand rays, selection, and comfort locomotion for
// Meta Quest 3. Uses the same pick pipeline as the desktop pointer.

import * as THREE from 'three';

const MAX_RAY = 6;
const SNAP_ANGLE = Math.PI / 6;
const MOVE_SPEED = 1.35;

function makeRay() {
  const geometry = new THREE.BufferGeometry().setFromPoints([
    new THREE.Vector3(0, 0, 0),
    new THREE.Vector3(0, 0, -1),
  ]);
  const material = new THREE.LineBasicMaterial({
    color: 0x5fe3ff,
    transparent: true,
    opacity: 0.45,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    fog: false,
  });
  const line = new THREE.Line(geometry, material);
  line.scale.z = MAX_RAY;
  line.renderOrder = 5;
  return line;
}

function makeWand(color = 0x5fe3ff) {
  const group = new THREE.Group();
  const body = new THREE.Mesh(
    new THREE.CylinderGeometry(0.011, 0.014, 0.1, 10),
    new THREE.MeshBasicMaterial({ color: 0x9fb4cc }),
  );
  body.rotation.x = Math.PI / 2;
  body.position.z = -0.045;
  const tip = new THREE.Mesh(
    new THREE.SphereGeometry(0.012, 12, 8),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.95 }),
  );
  tip.position.z = -0.1;
  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(0.022, 0.0025, 6, 24),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.7 }),
  );
  ring.position.z = -0.02;
  group.add(body, tip, ring);
  return group;
}

function makeCursor() {
  const mesh = new THREE.Mesh(
    new THREE.SphereGeometry(0.007, 10, 8),
    new THREE.MeshBasicMaterial({
      color: 0x5fe3ff,
      transparent: true,
      opacity: 0.95,
      depthTest: false,
      depthWrite: false,
    }),
  );
  mesh.visible = false;
  mesh.renderOrder = 60;
  return mesh;
}

export class XRSystem {
  constructor({ renderer, view, app }) {
    this.renderer = renderer;
    this.view = view;
    this.app = app;
    this.entries = [];
    this.raycaster = new THREE.Raycaster();
    this.entering = false;
    this.lastEntry = null;
    this.snapLatch = false;
    this.supported = null;
    this.sessionFrames = 0;

    this._setupControllers();
    this._bindSession();
  }

  _setupControllers() {
    const player = this.view.player;
    for (let index = 0; index < 2; index += 1) {
      const controller = this.renderer.xr.getController(index);
      controller.userData.handedness = index === 0 ? 'left' : 'right';
      const entry = {
        kind: 'controller',
        object: controller,
        index,
        handedness: index === 0 ? 'left' : 'right',
        line: makeRay(),
        cursor: makeCursor(),
        gamepad: null,
        inputSource: null,
        grip: this.renderer.xr.getControllerGrip(index),
        lastSelect: 0,
      };
      entry.line.visible = false;
      controller.add(entry.line);
      entry.grip.visible = false;
      entry.grip.add(makeWand(index === 0 ? 0x5fe3ff : 0xb6ff6b));
      controller.addEventListener('connected', (event) => {
        entry.inputSource = event.data;
        entry.handedness = event.data.handedness ?? entry.handedness;
        entry.gamepad = event.data.gamepad ?? null;
        entry.line.visible = true;
        entry.grip.visible = true;
      });
      controller.addEventListener('disconnected', () => {
        entry.inputSource = null;
        entry.gamepad = null;
        entry.line.visible = false;
        entry.grip.visible = false;
        entry.cursor.visible = false;
      });
      controller.addEventListener('selectstart', () => this._select(entry));
      player.add(controller);
      player.add(entry.grip);
      this.view.scene.add(entry.cursor);
      this.entries.push(entry);
    }

    // Hands, when the headset grants hand-tracking. Pinches dispatch select.
    for (let index = 0; index < 2; index += 1) {
      const hand = this.renderer.xr.getHand(index);
      const entry = {
        kind: 'hand',
        object: hand,
        index,
        handedness: index === 0 ? 'left' : 'right',
        line: makeRay(),
        cursor: makeCursor(),
        gamepad: null,
        inputSource: null,
        pinchSpark: null,
        lastSelect: 0,
      };
      entry.line.material.color.set(0xb6ff6b);
      entry.line.material.opacity = 0.3;
      entry.line.visible = false;
      hand.add(entry.line);
      const spark = new THREE.Mesh(
        new THREE.SphereGeometry(0.008, 10, 8),
        new THREE.MeshBasicMaterial({ color: 0xb6ff6b, transparent: true, opacity: 0.9 }),
      );
      spark.position.z = -0.03;
      spark.visible = false;
      hand.add(spark);
      entry.pinchSpark = spark;
      hand.addEventListener('connected', (event) => {
        entry.inputSource = event.data;
        entry.handedness = event.data.handedness ?? entry.handedness;
        entry.line.visible = true;
        entry.pinchSpark.visible = true;
      });
      hand.addEventListener('disconnected', () => {
        entry.inputSource = null;
        entry.line.visible = false;
        entry.pinchSpark.visible = false;
        entry.cursor.visible = false;
      });
      hand.addEventListener('selectstart', () => this._select(entry));
      // Some runtimes report pinches only through these events.
      hand.addEventListener('pinchstart', () => this._select(entry));
      player.add(hand);
      this.view.scene.add(entry.cursor);
      this.entries.push(entry);
    }
  }

  _bindSession() {
    this.renderer.xr.addEventListener('sessionstart', () => {
      this.sessionFrames = 0;
      this.view.setXR(true);
      this.app.setVR(true);
      this.view.panels.setEnabled(true);
      this.view.pendingRecenter = true;
    });
    this.renderer.xr.addEventListener('sessionend', () => {
      this.view.setXR(false);
      this.app.setVR(false);
      this.view.panels.setEnabled(false);
      this.sessionFrames = 0;
      for (const entry of this.entries) {
        entry.cursor.visible = false;
        entry.line.visible = false;
        if (entry.grip) entry.grip.visible = false;
        if (entry.pinchSpark) entry.pinchSpark.visible = false;
      }
      this.app.fit();
    });
  }

  async isSupported() {
    if (this.supported != null) return this.supported;
    if (!navigator.xr?.isSessionSupported) {
      this.supported = false;
      return false;
    }
    try {
      this.supported = await navigator.xr.isSessionSupported('immersive-vr');
    } catch {
      this.supported = false;
    }
    return this.supported;
  }

  async enter() {
    if (this.entering) return;
    if (this.renderer.xr.isPresenting) return;
    this.entering = true;
    try {
      if (!navigator.xr) {
        this.app.toast(
          'WebXR is not available here. Open this page in the Meta Quest Browser on your headset.',
          'error',
        );
        return;
      }
      if (this.supported === false) {
        this.app.toast(
          'This browser cannot start an immersive session. Open the Quest URL in the Meta Quest Browser, or use the flat preview on desktop.',
          'error',
        );
        return;
      }
      // Do not await anything before requestSession: Quest Browser requires
      // the call to stay inside the button's user activation.
      const session = await navigator.xr.requestSession('immersive-vr', {
        requiredFeatures: ['local-floor'],
        optionalFeatures: ['bounded-floor', 'hand-tracking'],
      });
      this.renderer.xr.setReferenceSpaceType('local-floor');
      await this.renderer.xr.setSession(session);
    } catch (error) {
      console.error('[mindme] could not enter VR', error);
      this.app.toast(`Could not enter VR: ${error.message}`, 'error');
    } finally {
      this.entering = false;
    }
  }

  pulse(entry = this.lastEntry) {
    const gamepad = entry?.gamepad ?? entry?.inputSource?.gamepad;
    const actuator = gamepad?.hapticActuators?.[0];
    try {
      actuator?.pulse?.(0.4, 35);
    } catch {
      // Haptics are optional.
    }
  }

  _raycasterFor(entry) {
    const matrix = new THREE.Matrix4().extractRotation(entry.object.matrixWorld);
    this.raycaster.ray.origin.setFromMatrixPosition(entry.object.matrixWorld);
    this.raycaster.ray.direction.set(0, 0, -1).applyMatrix4(matrix);
    return this.raycaster;
  }

  _targets(entry) {
    const raycaster = this._raycasterFor(entry);
    const panelHit = this.view.panels.pick(raycaster);
    const nodeHit = this.view.constellation.pick(raycaster);
    const panelDistance = panelHit ? raycaster.ray.origin.distanceTo(panelHit.hit.point) : Infinity;
    const nodeDistance = nodeHit ? nodeHit.distance : Infinity;
    if (panelHit && panelDistance <= nodeDistance) {
      return { type: 'panel', panelHit, distance: panelDistance, raycaster };
    }
    if (nodeHit) return { type: 'node', nodeHit, distance: nodeDistance, raycaster };
    return { type: null, raycaster };
  }

  _select(entry) {
    // A Quest pinch can dispatch both `selectstart` and `pinchstart`; only
    // the first should toggle a button.
    const now = performance.now();
    if (now - (entry.lastSelect || 0) < 280) return;
    entry.lastSelect = now;
    this.lastEntry = entry;
    const target = this._targets(entry);
    if (target.type === 'panel') {
      if (target.panelHit.hit.id) {
        this.view.panels.handleAction(target.panelHit.hit.id);
        this.pulse(entry);
      }
      return;
    }
    if (target.type === 'node') {
      this.app.select(target.nodeHit.node.id);
    }
  }

  update(dt) {
    if (!this.renderer.xr.isPresenting) return;

    // Wait for the first presented poses before placing the map and panels.
    this.sessionFrames += 1;
    if (this.view.pendingRecenter && this.sessionFrames > 2) {
      this.view.recenterXR();
    }

    this._locomotion(dt);

    let best = null;

    for (const entry of this.entries) {
      entry.cursor.visible = false;
      if (!entry.inputSource || !entry.object.visible) continue;

      const target = this._targets(entry);
      const length = Number.isFinite(target.distance) ? Math.min(MAX_RAY, target.distance) : MAX_RAY;
      entry.line.scale.z = length;
      entry.line.material.opacity = target.type ? 0.75 : 0.3;

      if (target.type) {
        const point = target.type === 'panel' ? target.panelHit.hit.point : target.nodeHit.point;
        entry.cursor.position.copy(point);
        entry.cursor.visible = true;
        if (!best || target.distance < best.target.distance) best = { entry, target };
      }
    }

    const hoverNode = best?.target.type === 'node' ? best.target.nodeHit.node.id : null;
    const hoverPanel = best?.target.type === 'panel' ? best.target.panelHit.panel : null;
    const hoverPanelID = best?.target.type === 'panel' ? best.target.panelHit.hit.id : null;

    this.view.constellation.setHover(hoverNode);
    for (const panel of [
      this.view.panels.control,
      this.view.panels.help,
      this.view.panels.empty,
      this.view.panels.inspector,
    ]) {
      panel.setHover(panel === hoverPanel ? hoverPanelID : null);
    }
  }

  _locomotion(dt) {
    const player = this.view.player;
    const forward = this.view.camera.getWorldDirection(new THREE.Vector3());
    forward.y = 0;
    if (forward.lengthSq() < 0.0001) forward.set(0, 0, -1);
    forward.normalize();
    const right = new THREE.Vector3().crossVectors(forward, new THREE.Vector3(0, 1, 0)).normalize();

    let moveX = 0;
    let moveY = 0;
    let turn = 0;
    let zoom = 0;
    let recenter = false;

    for (const entry of this.entries) {
      if (entry.kind !== 'controller' || !entry.gamepad) continue;
      const axes = entry.gamepad.axes ?? [];
      const x = axes[2] ?? axes[0] ?? 0;
      const y = axes[3] ?? axes[1] ?? 0;

      if (entry.handedness === 'left') {
        if (Math.abs(x) > 0.15) moveX += x;
        if (Math.abs(y) > 0.15) moveY += y;
      } else {
        if (Math.abs(x) > 0.7 && !this.snapLatch) {
          turn -= Math.sign(x) * SNAP_ANGLE;
          this.snapLatch = true;
        } else if (Math.abs(x) < 0.3) {
          this.snapLatch = false;
        }
        if (Math.abs(y) > 0.15) zoom -= y;
      }

      const button = entry.gamepad.buttons?.[4];
      if (button?.pressed && !entry.recenterLatch) {
        recenter = true;
        entry.recenterLatch = true;
      } else if (!button?.pressed) {
        entry.recenterLatch = false;
      }
    }

    if (moveX || moveY) {
      player.position.addScaledVector(forward, -moveY * MOVE_SPEED * dt);
      player.position.addScaledVector(right, moveX * MOVE_SPEED * dt);
    }
    if (turn) {
      // Snap turn around the head, not the room origin.
      const before = this.view.camera.getWorldPosition(new THREE.Vector3());
      player.rotation.y += turn;
      player.updateMatrixWorld(true);
      const after = this.view.camera.getWorldPosition(new THREE.Vector3());
      player.position.add(before.sub(after));
    }
    if (zoom) this.view.zoomXR(zoom * dt * 0.7);
    if (recenter) this.app.recenter();
  }
}
