// A tiny canvas-drawn HUD toolkit for world-space WebXR panels, plus the
// panel mesh wrapper that turns pointer/controller rays into button hits.

import * as THREE from 'three';
import { HUD } from '../theme.js';
import { FONT_MONO, FONT_SANS, roundedRect, withAlpha, wrapLines } from '../util.js';

export const DESIGN = { width: 1024, height: 768 };

export function drawBackdrop(ctx, width, height, { accent = HUD.accent, title = '' } = {}) {
  ctx.clearRect(0, 0, width, height);

  ctx.fillStyle = 'rgba(6, 10, 18, 0.985)';
  roundedRect(ctx, 0, 0, width, height, 22);
  ctx.fill();

  // Header tint + scanlines.
  const gradient = ctx.createLinearGradient(0, 0, 0, height);
  gradient.addColorStop(0, withAlpha(accent, 0.08));
  gradient.addColorStop(0.16, 'rgba(0,0,0,0)');
  ctx.fillStyle = gradient;
  roundedRect(ctx, 0, 0, width, height, 22);
  ctx.fill();

  ctx.save();
  roundedRect(ctx, 0, 0, width, height, 22);
  ctx.clip();
  ctx.fillStyle = 'rgba(255,255,255,0.018)';
  for (let y = 0; y < height; y += 4) ctx.fillRect(0, y, width, 1);
  ctx.restore();

  ctx.strokeStyle = 'rgba(255,255,255,0.12)';
  ctx.lineWidth = 2;
  roundedRect(ctx, 1, 1, width - 2, height - 2, 21);
  ctx.stroke();

  // Corner brackets.
  ctx.strokeStyle = withAlpha(accent, 0.8);
  ctx.lineWidth = 3;
  const inset = 16;
  const arm = 26;
  for (const [x, y, dx, dy] of [
    [inset, inset, 1, 1],
    [width - inset, inset, -1, 1],
    [inset, height - inset, 1, -1],
    [width - inset, height - inset, -1, -1],
  ]) {
    ctx.beginPath();
    ctx.moveTo(x + dx * arm, y);
    ctx.lineTo(x, y);
    ctx.lineTo(x, y + dy * arm);
    ctx.stroke();
  }

  if (title) {
    ctx.font = `600 15px ${FONT_MONO}`;
    ctx.fillStyle = withAlpha(accent, 0.75);
    ctx.textBaseline = 'top';
    ctx.letterSpacing = '3px';
    ctx.fillText(title, 44, 34);
    ctx.letterSpacing = '0px';
  }
}

export function drawText(ctx, text, x, y, options = {}) {
  const {
    size = 24,
    color = HUD.text,
    weight = 500,
    family = FONT_SANS,
    align = 'left',
    baseline = 'top',
    spacing = '0px',
    glow = null,
  } = options;
  ctx.font = `${weight} ${size}px ${family}`;
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.textBaseline = baseline;
  if ('letterSpacing' in ctx) ctx.letterSpacing = spacing;
  if (glow) {
    ctx.shadowColor = glow;
    ctx.shadowBlur = 18;
  }
  ctx.fillText(text, x, y);
  ctx.shadowBlur = 0;
  ctx.textAlign = 'left';
  if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
}

export function measureText(ctx, text, options = {}) {
  const { size = 24, weight = 500, family = FONT_SANS, spacing = '0px' } = options;
  ctx.save();
  ctx.font = `${weight} ${size}px ${family}`;
  if ('letterSpacing' in ctx) ctx.letterSpacing = spacing;
  const width = ctx.measureText(text).width;
  ctx.restore();
  return width;
}

/** Wraps and draws text; returns the next baseline y. */
export function drawWrapped(ctx, text, x, y, maxWidth, options = {}) {
  const {
    size = 20,
    lineHeight = size * 1.5,
    color = HUD.textSoft,
    weight = 400,
    family = FONT_SANS,
  } = options;
  ctx.font = `${weight} ${size}px ${family}`;
  ctx.fillStyle = color;
  ctx.textBaseline = 'top';
  const lines = wrapLines(ctx, text, maxWidth);
  let cursor = y;
  for (const line of lines) {
    ctx.fillText(line, x, cursor);
    cursor += lineHeight;
  }
  return cursor;
}

export function drawDivider(ctx, x, y, width, color = 'rgba(255,255,255,0.08)') {
  ctx.fillStyle = color;
  ctx.fillRect(x, y, width, 1);
}

export function drawStat(ctx, { x, y, width, height, value, label, accent = HUD.accent }) {
  ctx.fillStyle = 'rgba(255,255,255,0.02)';
  roundedRect(ctx, x, y, width, height, 10);
  ctx.fill();
  ctx.strokeStyle = 'rgba(255,255,255,0.08)';
  ctx.lineWidth = 1;
  roundedRect(ctx, x, y, width, height, 10);
  ctx.stroke();
  drawText(ctx, value, x + 14, y + 10, { size: 24, color: HUD.text, weight: 500, family: FONT_MONO });
  drawText(ctx, label, x + 14, y + height - 24, { size: 11, color: HUD.muted, family: FONT_MONO, spacing: '2px' });
}

/**
 * Registers and draws a button. `panel` supplies hover state. Returns the
 * rectangle for callers that want to position adjacent elements.
 */
export function drawButton(panel, ctx, {
  id,
  label,
  x,
  y,
  width,
  height = 52,
  active = false,
  tone = HUD.accent,
  size = 16,
  subtitle = null,
  disabled = false,
}) {
  const hovered = panel.hoverId === id;
  ctx.fillStyle = active
    ? withAlpha(tone, 0.18)
    : hovered
      ? 'rgba(255,255,255,0.09)'
      : 'rgba(255,255,255,0.025)';
  roundedRect(ctx, x, y, width, height, 9);
  ctx.fill();
  ctx.strokeStyle = active ? withAlpha(tone, 0.7) : hovered ? 'rgba(255,255,255,0.28)' : 'rgba(255,255,255,0.09)';
  ctx.lineWidth = active ? 2 : 1;
  roundedRect(ctx, x, y, width, height, 9);
  ctx.stroke();

  const textColor = disabled ? HUD.dim : active ? tone : hovered ? HUD.text : HUD.textSoft;
  drawText(ctx, subtitle ? label : label.toUpperCase(), x + width / 2, y + (subtitle ? 9 : height / 2), {
    size,
    color: textColor,
    family: FONT_MONO,
    weight: active ? 700 : 500,
    align: 'center',
    baseline: subtitle ? 'top' : 'middle',
    spacing: '1.5px',
  });
  if (subtitle) {
    drawText(ctx, subtitle, x + width / 2, y + height - 17, {
      size: 10,
      color: disabled ? HUD.dim : HUD.muted,
      family: FONT_MONO,
      align: 'center',
      spacing: '1px',
    });
  }

  if (!disabled) panel.addHitArea(id, x, y, width, height);
  return { x, y, width, height };
}

export function drawChip(panel, ctx, {
  id,
  label,
  x,
  y,
  width,
  height = 34,
  active = true,
  color = HUD.accent,
  size = 12,
}) {
  const hovered = panel.hoverId === id;
  ctx.fillStyle = active ? withAlpha(color, 0.14) : 'rgba(255,255,255,0.02)';
  roundedRect(ctx, x, y, width, height, height / 2);
  ctx.fill();
  ctx.strokeStyle = active ? withAlpha(color, 0.5) : hovered ? 'rgba(255,255,255,0.24)' : 'rgba(255,255,255,0.08)';
  ctx.lineWidth = 1;
  roundedRect(ctx, x, y, width, height, height / 2);
  ctx.stroke();

  ctx.fillStyle = active ? color : HUD.dim;
  ctx.beginPath();
  ctx.arc(x + 14, y + height / 2, 3.5, 0, Math.PI * 2);
  ctx.fill();

  drawText(ctx, label.toUpperCase(), x + 25, y + height / 2, {
    size,
    color: active ? HUD.text : HUD.muted,
    family: FONT_MONO,
    weight: 500,
    align: 'left',
    baseline: 'middle',
    spacing: '1px',
  });

  if (id) panel.addHitArea(id, x, y, width, height);
  return { x, y, width, height };
}

export function drawProgress(ctx, { x, y, width, progress, color = HUD.accent }) {
  ctx.fillStyle = 'rgba(255,255,255,0.06)';
  roundedRect(ctx, x, y, width, 5, 2.5);
  ctx.fill();
  ctx.fillStyle = withAlpha(color, 0.85);
  roundedRect(ctx, x, y, Math.max(4, width * Math.max(0, Math.min(1, progress))), 5, 2.5);
  ctx.fill();
}

// ------------------------------------------------------------------ panel

export class WorldPanel {
  constructor({ width, height, canvasWidth = DESIGN.width, canvasHeight = DESIGN.height, name = 'panel' }) {
    this.canvas = document.createElement('canvas');
    this.canvas.width = canvasWidth;
    this.canvas.height = canvasHeight;
    this.ctx = this.canvas.getContext('2d');

    this.texture = new THREE.CanvasTexture(this.canvas);
    this.texture.colorSpace = THREE.SRGBColorSpace;
    this.texture.minFilter = THREE.LinearFilter;
    this.texture.magFilter = THREE.LinearFilter;
    this.texture.generateMipmaps = false;

    this.material = new THREE.MeshBasicMaterial({
      map: this.texture,
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      toneMapped: false,
    });
    this.mesh = new THREE.Mesh(new THREE.PlaneGeometry(width, height), this.material);
    this.mesh.name = name;
    this.mesh.renderOrder = 50; // above labels (30) and cursors, so world text cannot bleed through
    this.mesh.visible = false;
    this.mesh.userData.panel = this;

    this.width = width;
    this.height = height;
    this.hitAreas = [];
    this.hoverId = null;
    this.renderer = null;
    this.dirty = true;
    this.lastDraw = 0;
    this._tmpTarget = new THREE.Vector3();
    this._tmpPosition = new THREE.Vector3();
    this._tmpQuat = new THREE.Quaternion();
    this._up = new THREE.Vector3(0, 1, 0);
  }

  setRenderer(renderer) {
    this.renderer = renderer;
    this.invalidate();
  }

  invalidate() {
    this.dirty = true;
  }

  draw(force = false) {
    if (!this.renderer) return;
    if (!force && !this.dirty) return;
    if (!force && performance.now() - this.lastDraw < 40) return;
    this.hitAreas = [];
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    this.renderer(this.ctx, this);
    this.texture.needsUpdate = true;
    this.lastDraw = performance.now();
    this.dirty = false;
  }

  addHitArea(id, x, y, width, height) {
    this.hitAreas.push({ id, x, y, width, height });
  }

  setHover(id) {
    if (id === this.hoverId) return;
    this.hoverId = id;
    this.invalidate();
    this.draw();
  }

  /** Returns `{ id, x, y }` for a ray hit, or null when the ray misses. */
  pick(raycaster) {
    if (!this.mesh.visible) return null;
    this.mesh.updateWorldMatrix(true, false);
    const hits = raycaster.intersectObject(this.mesh, false);
    if (!hits.length) return null;
    const uv = hits[0].uv;
    if (!uv) return { id: null, x: 0, y: 0, point: hits[0].point };
    const x = uv.x * this.canvas.width;
    const y = (1 - uv.y) * this.canvas.height;
    let id = null;
    for (let i = this.hitAreas.length - 1; i >= 0; i -= 1) {
      const area = this.hitAreas[i];
      if (x >= area.x && x <= area.x + area.width && y >= area.y && y <= area.y + area.height) {
        id = area.id;
        break;
      }
    }
    return { id, x, y, point: hits[0].point };
  }

  setVisible(visible) {
    this.mesh.visible = visible;
    if (visible) this.draw(true);
  }

  /** Yaw-only billboard so text stays upright and readable. */
  faceCamera(camera, dt = 0.016) {
    if (!this.mesh.visible) return;
    this.mesh.updateWorldMatrix(true, false);
    camera.getWorldPosition(this._tmpTarget);
    this.mesh.getWorldPosition(this._tmpPosition);
    const angle = Math.atan2(
      this._tmpTarget.x - this._tmpPosition.x,
      this._tmpTarget.z - this._tmpPosition.z,
    );
    this._tmpQuat.setFromAxisAngle(this._up, angle);
    const alpha = 1 - Math.pow(0.0008, dt);
    this.mesh.quaternion.slerp(this._tmpQuat, alpha);
  }

  /** Position and orientation for "in front of the head" placement. */
  placeInFrontOf(headPosition, yaw, { distance = 1.6, lateral = 0, height = 1.45 }) {
    const forward = new THREE.Vector3(Math.sin(yaw), 0, -Math.cos(yaw));
    const right = new THREE.Vector3(Math.cos(yaw), 0, Math.sin(yaw));
    const position = headPosition
      .clone()
      .addScaledVector(forward, distance)
      .addScaledVector(right, lateral);
    position.y = height;
    this.mesh.position.copy(position);
    // Plane normal (+Z) must point back toward the viewer.
    this._tmpQuat.setFromAxisAngle(this._up, -yaw);
    this.mesh.quaternion.copy(this._tmpQuat);
    this.mesh.updateWorldMatrix(true, false);
  }

  dispose() {
    this.mesh.geometry.dispose();
    this.material.dispose();
    this.texture.dispose();
    this.mesh.removeFromParent();
  }
}

export function headerTitle(ctx, text, subtitle = null, { accent = HUD.accent } = {}) {
  drawText(ctx, text, 44, 62, { size: 32, color: HUD.text, weight: 600, family: FONT_SANS });
  if (subtitle) {
    drawText(ctx, subtitle, 44, 104, { size: 13, color: HUD.muted, family: FONT_MONO, spacing: '2px' });
  }
  ctx.fillStyle = accent;
  ctx.fillRect(44, subtitle ? 124 : 106, 52, 3);
}
