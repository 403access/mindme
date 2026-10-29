// Canvas-texture labels for the spatial map. Sprites stay legible in VR
// because they are sized in world units and drawn at high canvas resolution.

import * as THREE from 'three';
import { FONT_MONO } from '../util.js';

const measureCanvas = document.createElement('canvas');
const measureCtx = measureCanvas.getContext('2d');

export function makeLabelSprite({ title, subtitle = '', color = '#E9F1FF', subtitleColor = '#71809A' }) {
  // Long conversation titles would otherwise generate enormous textures.
  title = String(title ?? '').slice(0, 84);
  subtitle = String(subtitle ?? '').slice(0, 64);
  const titleSize = 46;
  const subtitleSize = 30;
  const padX = 26;
  const padY = 16;
  const gap = subtitle ? 8 : 0;

  measureCtx.font = `600 ${titleSize}px ${FONT_MONO}`;
  const titleWidth = measureCtx.measureText(title).width;
  let subtitleWidth = 0;
  if (subtitle) {
    measureCtx.font = `500 ${subtitleSize}px ${FONT_MONO}`;
    subtitleWidth = measureCtx.measureText(subtitle).width;
  }

  const width = Math.ceil(Math.max(titleWidth, subtitleWidth) + padX * 2);
  const height = Math.ceil(titleSize + padY * 2 + (subtitle ? subtitleSize + gap : 0));

  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');

  // Faint plate keeps labels readable over bright nodes and edges.
  ctx.fillStyle = 'rgba(4, 6, 11, 0.58)';
  ctx.beginPath();
  const r = 12;
  ctx.moveTo(r, 0);
  ctx.arcTo(width, 0, width, height, r);
  ctx.arcTo(width, height, 0, height, r);
  ctx.arcTo(0, height, 0, 0, r);
  ctx.arcTo(0, 0, width, 0, r);
  ctx.closePath();
  ctx.fill();

  ctx.textBaseline = 'top';
  ctx.textAlign = 'left';
  ctx.font = `600 ${titleSize}px ${FONT_MONO}`;
  ctx.shadowColor = color;
  ctx.shadowBlur = 16;
  ctx.fillStyle = color;
  ctx.fillText(title, padX, padY);
  ctx.shadowBlur = 0;

  if (subtitle) {
    ctx.font = `500 ${subtitleSize}px ${FONT_MONO}`;
    ctx.fillStyle = subtitleColor;
    ctx.fillText(subtitle, padX, padY + titleSize + gap);
  }

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.minFilter = THREE.LinearMipmapLinearFilter;
  texture.magFilter = THREE.LinearFilter;
  texture.generateMipmaps = true;
  texture.anisotropy = 4;
  texture.needsUpdate = true;

  const material = new THREE.SpriteMaterial({
    map: texture,
    transparent: true,
    depthTest: false,
    depthWrite: false,
    fog: false,
  });
  const sprite = new THREE.Sprite(material);
  sprite.renderOrder = 30;
  sprite.userData.aspect = width / height;
  // Angular size factor for constant screen-space labels (set by callers).
  sprite.userData.factor = 0.02;
  sprite.userData.labelKind = 'node';
  return sprite;
}

/**
 * Initial height in layout units. `updateLabelScale` keeps the label at a
 * constant angular size afterwards, so text stays legible at any distance.
 */
export function sizeLabelSprite(sprite, height) {
  const aspect = sprite.userData.aspect ?? 4;
  sprite.scale.set(height * aspect, height, 1);
  sprite.userData.baseHeight = height;
  return sprite;
}

export function disposeLabel(sprite) {
  if (!sprite) return;
  sprite.material.map?.dispose();
  sprite.material.dispose();
  sprite.removeFromParent();
}
