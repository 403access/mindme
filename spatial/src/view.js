// Renderer, scene, desktop orbit camera, floor, ambient starfield, and the
// bridge between the flat preview and the headset's room-scale space.

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { Constellation } from './render/constellation.js';
import { Panels } from './ui/panels.js';

const BASE_SCALE = 0.0034; // layout units → metres
const MIN_ZOOM = 0.55;
const MAX_ZOOM = 1.9;

export class View {
  constructor({ canvas, app }) {
    this.canvas = canvas;
    this.app = app;
    this.isVR = false;
    this.motion = true;
    this.mapZoom = 1;
    this.pendingRecenter = false;
    this.pointer = new THREE.Vector2(0, 0);
    this.raycaster = new THREE.Raycaster();
    this.hoverNodeID = null;
    this.pointerDown = null;
    this.lastHoverCheck = 0;

    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      alpha: false,
      powerPreference: 'high-performance',
      stencil: false,
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.NoToneMapping;
    this.renderer.xr.enabled = true;
    this.renderer.xr.setReferenceSpaceType('local-floor');
    this.renderer.xr.setFramebufferScaleFactor(1);

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x04060b);
    this.scene.fog = new THREE.FogExp2(0x04060b, 0.048);

    this.camera = new THREE.PerspectiveCamera(58, 1, 0.04, 140);
    this.player = new THREE.Group();
    this.player.name = 'player';
    this.player.add(this.camera);
    this.scene.add(this.player);
    this.camera.position.set(0, 2.15, 5.6);

    this.controls = new OrbitControls(this.camera, canvas);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.075;
    this.controls.target.set(0, 1.4, 0);
    this.controls.minDistance = 1.1;
    this.controls.maxDistance = 16;
    this.controls.maxPolarAngle = Math.PI * 0.94;
    this.controls.zoomSpeed = 0.8;
    this.controls.update();

    this.constellation = new Constellation(this.scene);
    this.constellation.group.position.set(0, 1.5, 0);
    this.constellation.group.scale.setScalar(BASE_SCALE);

    this.panels = new Panels(app, this.scene);
    this.panels.setEnabled(false);

    this._buildEnvironment();
    this._bindDesktopInput();

    canvas.addEventListener('webglcontextlost', (event) => {
      event.preventDefault();
      this.app.toast('The graphics context was lost. If the headset stops rendering, exit VR and re-enter.', 'error');
    });
    this.resize();
    window.addEventListener('resize', () => this.resize());
    window.addEventListener('orientationchange', () => this.resize());
  }

  // ---------------------------------------------------------- environment

  _buildEnvironment() {
    const floor = new THREE.Group();
    floor.name = 'floor';

    const grid = new THREE.GridHelper(26, 52, 0x1a4360, 0x0b1c2a);
    grid.position.y = 0;
    grid.material.transparent = true;
    grid.material.opacity = 0.28;
    grid.material.depthWrite = false;
    floor.add(grid);

    const polar = new THREE.PolarGridHelper(8.5, 16, 6, 72, 0x1d5677, 0x0d2637);
    polar.position.y = 0.002;
    polar.material.transparent = true;
    polar.material.opacity = 0.22;
    polar.material.depthWrite = false;
    floor.add(polar);

    const rings = [
      [2.1, 0.05],
      [3.4, 0.04],
      [5.2, 0.03],
    ];
    for (const [radius, opacity] of rings) {
      const ring = new THREE.Mesh(
        new THREE.RingGeometry(radius, radius + 0.006, 96),
        new THREE.MeshBasicMaterial({
          color: 0x5fe3ff,
          transparent: true,
          opacity,
          side: THREE.DoubleSide,
          depthWrite: false,
        }),
      );
      ring.rotation.x = -Math.PI / 2;
      ring.position.y = 0.004;
      floor.add(ring);
    }

    // Ground glow under the constellation.
    const glow = new THREE.Mesh(
      new THREE.CircleGeometry(3.6, 64),
      new THREE.MeshBasicMaterial({
        map: makeGlowTexture(),
        transparent: true,
        opacity: 0.22,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
      }),
    );
    glow.rotation.x = -Math.PI / 2;
    glow.position.y = 0.006;
    floor.add(glow);

    this.scene.add(floor);
    this.floor = floor;

    const starCount = 900;
    const positions = new Float32Array(starCount * 3);
    for (let i = 0; i < starCount; i += 1) {
      const radius = 14 + Math.random() * 26;
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos(2 * Math.random() - 1);
      positions[i * 3] = radius * Math.sin(phi) * Math.cos(theta);
      positions[i * 3 + 1] = Math.abs(radius * Math.cos(phi)) * 0.6 + 0.4;
      positions[i * 3 + 2] = radius * Math.sin(phi) * Math.sin(theta);
    }
    const starGeometry = new THREE.BufferGeometry();
    starGeometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const stars = new THREE.Points(
      starGeometry,
      new THREE.PointsMaterial({
        color: 0x9fd8ff,
        size: 0.025,
        transparent: true,
        opacity: 0.5,
        depthWrite: false,
        sizeAttenuation: true,
        fog: false,
      }),
    );
    stars.name = 'stars';
    this.scene.add(stars);
  }

  // ------------------------------------------------------------- desktop

  _bindDesktopInput() {
    const canvas = this.canvas;

    canvas.addEventListener('pointermove', (event) => {
      if (this.isVR) return;
      const rect = canvas.getBoundingClientRect();
      this.pointer.set(
        ((event.clientX - rect.left) / rect.width) * 2 - 1,
        -((event.clientY - rect.top) / rect.height) * 2 + 1,
      );
      const now = performance.now();
      if (now - this.lastHoverCheck < 60) return;
      this.lastHoverCheck = now;
      this._updateDesktopHover();
    });

    canvas.addEventListener('pointerleave', () => {
      if (this.isVR) return;
      this._setHover(null);
      canvas.style.cursor = '';
    });

    canvas.addEventListener('pointerdown', (event) => {
      if (this.isVR) return;
      this.pointerDown = { x: event.clientX, y: event.clientY };
    });

    canvas.addEventListener('pointerup', (event) => {
      if (this.isVR) return;
      const start = this.pointerDown;
      this.pointerDown = null;
      if (!start) return;
      const travelled = Math.hypot(event.clientX - start.x, event.clientY - start.y);
      if (travelled > 10) return;
      const hit = this.pickAt(event.clientX, event.clientY);
      if (hit?.node) this.app.select(hit.node.id);
    });

    window.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') this.app.deselect();
      if ((event.metaKey || event.ctrlKey) && (event.key === 'f' || event.key === 'F')) {
        event.preventDefault();
        document.getElementById('search-input')?.focus();
        return;
      }
      if (event.target instanceof HTMLInputElement) return;
      if (event.key === 'f' || event.key === 'F' || event.key === '0') this.fit();
      if (event.key === 'r' || event.key === 'R') this.app.recenter();
    });
  }

  pickAt(clientX, clientY) {
    const rect = this.canvas.getBoundingClientRect();
    this.pointer.set(
      ((clientX - rect.left) / rect.width) * 2 - 1,
      -((clientY - rect.top) / rect.height) * 2 + 1,
    );
    this.raycaster.setFromCamera(this.pointer, this.camera);
    return this.constellation.pick(this.raycaster);
  }

  _updateDesktopHover() {
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const hit = this.constellation.pick(this.raycaster);
    this._setHover(hit?.node.id ?? null);
    this.canvas.style.cursor = hit ? 'pointer' : '';
  }

  _setHover(nodeID) {
    if (nodeID === this.hoverNodeID) return;
    this.hoverNodeID = nodeID;
    this.constellation.setHover(nodeID);
  }

  // ------------------------------------------------------------ graph

  setGraph(graph, { selected = null, fit = false } = {}) {
    this.constellation.build(graph);
    this.constellation.setLabels(this.app.filters.showLabels);
    this.constellation.setSpend(this.app.filters.spend);
    this.constellation.setFocus(selected);
    if (!this.isVR && fit) this.fit();

    // Tags/paths may change under the pointer.
    if (!this.isVR) this._updateDesktopHover();
  }

  fit() {
    if (this.isVR) {
      this.mapZoom = 1;
      this.constellation.group.scale.setScalar(BASE_SCALE);
      this.recenterXR();
      return;
    }
    const anchors = this.constellation.anchors;
    if (!anchors.size) return;

    const box = new THREE.Box3();
    for (const point of anchors.values()) box.expandByPoint(point);
    const sphere = box.getBoundingSphere(new THREE.Sphere());
    const radius = Math.max(0.9, sphere.radius * BASE_SCALE);
    const worldCenter = sphere.center
      .clone()
      .multiplyScalar(BASE_SCALE)
      .add(this.constellation.group.position);

    const fov = (this.camera.fov * Math.PI) / 180;
    const distance = (radius / Math.sin(fov / 2)) * 0.8;
    const direction = new THREE.Vector3(0.24, 0.26, 1).normalize();
    this.camera.position.copy(worldCenter).addScaledVector(direction, distance);
    this.controls.target.copy(worldCenter);
    this.camera.lookAt(worldCenter);
    this.controls.minDistance = Math.max(0.6, radius * 0.25);
    this.controls.maxDistance = Math.max(8, radius * 6);
    this.controls.update();
  }

  setMotion(enabled) {
    this.motion = enabled;
    if (!enabled) this.constellation.group.rotation.y = 0;
  }

  // --------------------------------------------------------------- XR

  setXR(active) {
    this.isVR = active;
    this.controls.enabled = !active;
    this._setHover(null);
    this.canvas.style.cursor = '';

    if (active) {
      this.player.position.set(0, 0, 0);
      this.player.rotation.set(0, 0, 0);
      this.constellation.group.visible = false;
      this.pendingRecenter = true;
    } else {
      this.player.position.set(0, 0, 0);
      this.player.rotation.set(0, 0, 0);
      this.camera.position.set(0, 2.15, 5.6);
      this.controls.target.set(0, 1.4, 0);
      this.constellation.group.position.set(0, 1.5, 0);
      this.constellation.group.rotation.set(0, 0, 0);
      this.constellation.group.visible = true;
      this.mapZoom = 1;
      this.constellation.group.scale.setScalar(BASE_SCALE);
      this.fit();
    }
  }

  /** Puts the constellation and panels in front of the headset. */
  recenterXR() {
    if (!this.renderer.xr.isPresenting) return;
    const head = this.camera.getWorldPosition(new THREE.Vector3());
    const forward = this.camera.getWorldDirection(new THREE.Vector3());
    forward.y = 0;
    if (forward.lengthSq() < 0.0001) forward.set(0, 0, -1);
    forward.normalize();

    const eye = head.y || 1.6;
    const center = head.clone().addScaledVector(forward, 3.0);
    center.y = Math.max(1.15, Math.min(1.55, eye - 0.18));

    this.constellation.group.position.copy(center);
    this.constellation.group.rotation.set(0, 0, 0);
    this.constellation.group.scale.setScalar(BASE_SCALE * this.mapZoom);
    this.constellation.group.visible = true;
    this.panels.placeForXR(this.camera);
    this.pendingRecenter = false;
  }

  zoomXR(delta) {
    this.mapZoom = THREE.MathUtils.clamp(this.mapZoom * (1 + delta), MIN_ZOOM, MAX_ZOOM);
    this.constellation.group.scale.setScalar(BASE_SCALE * this.mapZoom);
  }

  // -------------------------------------------------------------- frame

  resize() {
    const width = window.innerWidth;
    const height = window.innerHeight;
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / Math.max(1, height);
    this.camera.updateProjectionMatrix();
  }

  update(dt) {
    if (!this.isVR) this.controls.update();

    if (this.motion) {
      const t = performance.now() / 1000;
      this.constellation.group.rotation.y = Math.sin(t * 0.16) * 0.04;
    }

    this.constellation.update(dt, this.camera);
    this.panels.update(dt, this.camera);
  }

  render() {
    this.renderer.render(this.scene, this.camera);
  }
}

function makeGlowTexture() {
  const size = 256;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  const gradient = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  gradient.addColorStop(0, 'rgba(95, 227, 255, 0.55)');
  gradient.addColorStop(0.45, 'rgba(60, 140, 200, 0.18)');
  gradient.addColorStop(1, 'rgba(0, 0, 0, 0)');
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}
