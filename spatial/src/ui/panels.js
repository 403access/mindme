// World-space HUD panels for VR: map controls, thread inspector, field guide,
// and an empty-signal card. The same data drives the flat DOM HUD on desktop.

import * as THREE from 'three';
import { HUD, MONO, PROVIDERS, providerMeta } from '../theme.js';
import { fmtCompact, fmtCount, fmtDate, fmtDateTime, fmtMoney, truncate, wrapLines, FONT_MONO } from '../util.js';
import { summarizeGraph } from '../data/graph.js';
import { prettyLabel } from '../data/keywords.js';
import {
  drawBackdrop,
  drawButton,
  drawChip,
  drawDivider,
  drawProgress,
  drawStat,
  drawText,
  drawWrapped,
  headerTitle,
  measureText,
  WorldPanel,
} from './panelKit.js';

const PANEL_W = 1024;
const PANEL_H = 768;

function sectionLabel(ctx, text, x, y) {
  drawText(ctx, text, x, y, { size: 12, color: HUD.muted, family: FONT_MONO, spacing: '2.5px' });
}

function roleLabel(role) {
  return { user: 'YOU', assistant: 'ASSISTANT', system: 'SYSTEM', tool: 'TOOL' }[role] ?? String(role).toUpperCase();
}

function nodeById(app, id) {
  return app.graph?.nodes.find((node) => node.id === id) ?? null;
}

function threadById(app, id) {
  return app.library?.threads.find((thread) => thread.id === id) ?? null;
}

function tagsForNode(app, node) {
  if (!node) return [];
  if (node.kind === 'thread') return app.graph.keywordsByThread.get(node.threadID) ?? [];
  if (node.kind === 'tag') return [{ term: node.tag, score: 0 }];
  return [];
}

// ------------------------------------------------------------- controls

export function createControlPanel(app) {
  const panel = new WorldPanel({ width: 1.02, height: 0.765, name: 'control-panel' });
  panel.setRenderer((ctx) => {
    const stats = app.graph?.stats;
    drawBackdrop(ctx, PANEL_W, PANEL_H, { title: 'MINDME // SPATIAL' });
    headerTitle(ctx, 'CONSTELLATION CONTROL', 'WEBXR · META QUEST 3 · LOCAL LIBRARY');

    // Stats ------------------------------------------------------------
    const statWidth = (PANEL_W - 88 - 16) / 3;
    drawStat(ctx, {
      x: 44,
      y: 142,
      width: statWidth,
      height: 66,
      value: fmtCompact(stats?.threadCount ?? 0),
      label: 'THREADS',
    });
    drawStat(ctx, {
      x: 44 + statWidth + 8,
      y: 142,
      width: statWidth,
      height: 66,
      value: fmtCompact(stats?.messageCount ?? 0),
      label: 'MESSAGES',
    });
    drawStat(ctx, {
      x: 44 + (statWidth + 8) * 2,
      y: 142,
      width: statWidth,
      height: 66,
      value: stats?.costThreadCount ? fmtMoney(stats.totalCost) : String(stats?.tagCount ?? 0),
      label: stats?.costThreadCount ? 'REPORTED SPEND' : 'SHARED TAGS',
    });

    // Lens -------------------------------------------------------------
    sectionLabel(ctx, 'LENS', 44, 234);
    const lensY = 254;
    const lensWidth = 196;
    ['provider', 'topic', 'era'].forEach((mode, index) => {
      drawButton(panel, ctx, {
        id: `group:${mode}`,
        label: mode,
        x: 44 + index * (lensWidth + 8),
        y: lensY,
        width: lensWidth,
        height: 46,
        active: app.filters.grouping === mode,
      });
    });
    drawText(ctx, `${fmtCount(stats?.groupCount ?? 0, 'CONSTELLATION', 'CONSTELLATIONS')} · ${fmtCount(stats?.tagCount ?? 0, 'TAG', 'TAGS')}`, 700, 260, {
      size: 12,
      color: HUD.muted,
      family: FONT_MONO,
      align: 'right',
      spacing: '1px',
    });

    // Providers --------------------------------------------------------
    sectionLabel(ctx, 'SOURCES', 44, 326);
    let chipX = 44;
    const chipY = 347;
    const chipHeight = 36;
    for (const provider of PROVIDERS) {
      const count = app.library?.threads.filter((thread) => thread.provider === provider.id).length ?? 0;
      const label = `${provider.name} ${count}`;
      const width = measureText(ctx, label, { size: 13, family: FONT_MONO }) + 54;
      drawChip(panel, ctx, {
        id: `provider:${provider.id}`,
        label,
        x: chipX,
        y: chipY,
        width,
        height: chipHeight,
        active: app.filters.providers.has(provider.id),
        color: provider.color,
        size: 13,
      });
      chipX += width + 8;
    }

    // Window -----------------------------------------------------------
    sectionLabel(ctx, 'WINDOW', 44, 410);
    const windowY = 431;
    const windowWidth = 196;
    [
      ['all', 'ALL TIME'],
      ['year', 'LAST 12M'],
      ['ninety', 'LAST 90D'],
      ['thirty', 'LAST 30D'],
    ].forEach(([id, label], index) => {
      drawButton(panel, ctx, {
        id: `window:${id}`,
        label,
        x: 44 + index * (windowWidth + 8),
        y: windowY,
        width: windowWidth,
        height: 44,
        active: app.timeWindow === id,
        size: 15,
      });
    });

    // View toggles -----------------------------------------------------
    const costAvailable = (stats?.costThreadCount ?? 0) > 0;
    sectionLabel(ctx, 'SIGNAL', 44, 496);
    const toggleY = 517;
    const toggleWidth = 180;
    [
      ['tags', 'TAGS', app.filters.includeTags, true],
      ['labels', 'LABELS', app.filters.showLabels, true],
      ['motion', 'MOTION', app.filters.motion, true],
      ['spend', 'SPEND', app.filters.spend, costAvailable],
    ].forEach(([id, label, active, enabled], index) => {
      drawButton(panel, ctx, {
        id: `toggle:${id}`,
        label,
        x: 44 + index * (toggleWidth + 8),
        y: toggleY,
        width: toggleWidth,
        height: 44,
        active,
        size: 15,
        disabled: !enabled,
      });
    });

    // Actions ----------------------------------------------------------
    const actionY = 592;
    const actions = [
      ['action:fit', 'FIT MAP', HUD.accent],
      ['action:clear', 'CLEAR FOCUS', HUD.accent],
      ['action:recenter', 'RECENTER', HUD.accent],
      ['action:help', 'GUIDE', HUD.lime],
    ];
    const actionWidth = 218;
    actions.forEach(([id, label, tone], index) => {
      drawButton(panel, ctx, {
        id,
        label,
        x: 44 + index * (actionWidth + 8),
        y: actionY,
        width: actionWidth,
        height: 48,
        tone,
        size: 15,
      });
    });

    drawDivider(ctx, 44, 664, PANEL_W - 88);
    drawText(ctx, 'TRIGGER  SELECT   ·   LEFT STICK  MOVE   ·   RIGHT STICK  TURN / ZOOM   ·   A/X  RECENTER', 44, 682, {
      size: 12,
      color: HUD.muted,
      family: FONT_MONO,
      spacing: '1px',
    });
    const footer = app.filters.spend
      ? 'SPEND HEAT ON — COSTS COME FROM OPENCODE ARCHIVES'
      : costAvailable
        ? 'DATA STAYS ON THIS HEADSET'
        : 'NO PROVIDER-REPORTED COST IN THIS LIBRARY';
    drawText(ctx, footer, 44, 708, {
      size: 12,
      color: app.filters.spend ? HUD.amber : HUD.dim,
      family: FONT_MONO,
      spacing: '1px',
    });

    const visible = stats?.threadCount ?? 0;
    drawText(ctx, summarizeGraph(app.graph), PANEL_W - 44, 714, {
      size: 10,
      color: HUD.muted,
      family: FONT_MONO,
      align: 'right',
      spacing: '0.5px',
    });
    drawProgress(ctx, {
      x: 44,
      y: 730,
      width: PANEL_W - 88,
      progress: visible / Math.max(1, stats?.unfilteredThreadCount ?? 1),
      color: HUD.accent,
    });
  });
  return panel;
}

// ------------------------------------------------------------ inspector

function buildTranscriptPages(app, thread) {
  const ctx = document.createElement('canvas').getContext('2d');
  const width = PANEL_W - 88;
  const lines = [];
  for (const message of thread.messages) {
    const stamp = message.timestamp ? fmtDateTime(message.timestamp) : '';
    lines.push({
      kind: 'role',
      text: stamp ? `${roleLabel(message.role)} · ${stamp}` : roleLabel(message.role),
      color: message.role === 'user' ? HUD.accent : HUD.muted,
      height: 20,
    });
    ctx.font = `400 18px ${MONO}`;
    const wrapped = wrapLines(ctx, message.text, width);
    for (const text of wrapped) {
      lines.push({
        kind: 'text',
        text,
        color: message.role === 'user' ? HUD.text : HUD.textSoft,
        height: 25,
      });
    }
    lines.push({ kind: 'gap', text: '', height: 12 });
  }

  const maxHeight = 330;
  const pages = [];
  let page = [];
  let used = 0;
  for (const line of lines) {
    if (used + line.height > maxHeight && page.length) {
      pages.push(page);
      page = [];
      used = 0;
    }
    page.push(line);
    used += line.height;
  }
  if (page.length) pages.push(page);
  return pages.length ? pages : [[{ kind: 'text', text: 'No transcript available.', color: HUD.muted, height: 20 }]];
}

export function createInspectorPanel(app, state) {
  const panel = new WorldPanel({ width: 1.02, height: 0.765, name: 'inspector-panel' });
  panel.setRenderer((ctx) => {
    const node = nodeById(app, state.nodeID);
    drawBackdrop(ctx, PANEL_W, PANEL_H, { title: 'MINDME // INSPECTOR' });
    if (!node) {
      headerTitle(ctx, 'NO SELECTION');
      drawWrapped(ctx, 'Point at a node and press the trigger to open its transcript, metadata, and shared tags.', 44, 160, PANEL_W - 88, {
        size: 18,
        color: HUD.textSoft,
      });
      drawButton(panel, ctx, {
        id: 'action:close',
        label: 'CLOSE',
        x: PANEL_W - 44 - 220,
        y: PANEL_H - 92,
        width: 220,
        height: 48,
        size: 14,
      });
      return;
    }

    const stats = app.graph.stats;
    if (node.kind === 'thread') {
      const thread = threadById(app, node.threadID);
      const provider = providerMeta(thread?.provider ?? 'other');
      drawText(ctx, `THREAD · ${provider.name.toUpperCase()}`, 44, 58, {
        size: 12,
        color: provider.color,
        family: FONT_MONO,
        spacing: '3px',
      });
      drawText(ctx, truncate(node.label, 62), 44, 80, { size: 30, color: HUD.text, weight: 600 });
      const meta = [
        thread?.model ? thread.model : provider.name,
        thread ? fmtDate(thread.createdAt) : '',
        fmtCount(thread?.messageCount ?? 0, 'MESSAGE', 'MESSAGES'),
        thread?.tokenCount ? `${fmtCompact(thread.tokenCount)} TOKENS` : null,
        thread?.hasCostData ? fmtMoney(thread.totalCost) : null,
      ].filter(Boolean);
      drawText(ctx, meta.join('  ·  '), 44, 120, { size: 13, color: HUD.muted, family: FONT_MONO, spacing: '0.8px' });

      const tags = tagsForNode(app, node).slice(0, 4);
      let tagX = 44;
      tags.forEach((tag) => {
        const label = prettyLabel(tag.term);
        const width = measureText(ctx, label, { size: 13, family: FONT_MONO }) + 36;
        const tagNode = app.graph.nodes.find((item) => item.kind === 'tag' && item.tag === tag.term);
        drawChip(panel, ctx, {
          id: tagNode ? `focus:${tagNode.id}` : null,
          label,
          x: tagX,
          y: 148,
          width,
          height: 32,
          active: Boolean(tagNode),
          color: HUD.magenta,
          size: 13,
        });
        tagX += width + 6;
      });
      if (tags.length) {
        drawText(ctx, 'CLICK A TAG TO ISOLATE ITS THREADS', PANEL_W - 44, 156, {
          size: 10,
          color: HUD.dim,
          family: FONT_MONO,
          align: 'right',
          spacing: '1px',
        });
      }

      drawDivider(ctx, 44, 196, PANEL_W - 88);
      drawText(ctx, 'TRANSCRIPT', 44, 208, { size: 11, color: HUD.muted, family: FONT_MONO, spacing: '2px' });

      const pages =
        state.cache?.nodeID === node.id
          ? state.cache.pages
          : thread
            ? buildTranscriptPages(app, thread)
            : [[{ kind: 'text', text: 'This conversation is outside the current filter.', color: HUD.muted, height: 20 }]];
      if (state.cache?.nodeID !== node.id) {
        state.cache = { nodeID: node.id, pages };
        state.page = 0;
      }
      const pageIndex = Math.max(0, Math.min(state.page, pages.length - 1));
      state.page = pageIndex;
      const page = pages[pageIndex] ?? [];
      let y = 240;
      for (const line of page) {
        if (line.kind === 'role') {
          drawText(ctx, line.text, 44, y, { size: 11, color: line.color, family: FONT_MONO, spacing: '1.5px' });
        } else if (line.kind === 'text') {
          drawText(ctx, line.text, 44, y, { size: 18, color: line.color, family: FONT_MONO });
        }
        y += line.height;
      }

      const footerY = PANEL_H - 92;
      drawDivider(ctx, 44, footerY - 18, PANEL_W - 88);
      drawButton(panel, ctx, {
        id: 'action:prev',
        label: '◀ PREV',
        x: 44,
        y: footerY,
        width: 150,
        height: 48,
        size: 13,
        disabled: pageIndex <= 0,
      });
      drawButton(panel, ctx, {
        id: 'action:next',
        label: 'NEXT ▶',
        x: 202,
        y: footerY,
        width: 150,
        height: 48,
        size: 13,
        disabled: pageIndex >= pages.length - 1,
      });
      drawText(ctx, `${pageIndex + 1} / ${pages.length}`, 388, footerY + 24, {
        size: 12,
        color: HUD.muted,
        family: FONT_MONO,
        baseline: 'middle',
        spacing: '1px',
      });
      drawButton(panel, ctx, {
        id: 'action:close',
        label: 'CLOSE',
        x: PANEL_W - 44 - 190,
        y: footerY,
        width: 190,
        height: 48,
        size: 13,
      });
      return;
    }

    // Group / tag / root inspectors -------------------------------------
    const kicker =
      node.kind === 'group' ? 'CONSTELLATION' : node.kind === 'tag' ? 'SHARED KEYWORD' : 'ROOT';
    drawText(ctx, kicker, 44, 58, { size: 12, color: HUD.accent, family: FONT_MONO, spacing: '3px' });
    drawText(ctx, truncate(node.label, 56), 44, 80, { size: 32, color: HUD.text, weight: 600 });
    drawText(ctx, node.subtitle ?? '', 44, 120, { size: 12, color: HUD.muted, family: FONT_MONO, spacing: '1px' });

    const memberIDs =
      node.kind === 'group'
        ? node.threadIDs ?? []
        : node.kind === 'tag'
          ? app.graph.edges.filter((edge) => edge.target === node.id).map((edge) => edge.source)
          : app.graph.nodes.filter((item) => item.kind === 'thread').map((item) => item.id);
    const members = memberIDs.map((id) => threadById(app, id.replace(/^thread:/, ''))).filter(Boolean);

    const statWidth = (PANEL_W - 88 - 16) / 3;
    drawStat(ctx, {
      x: 44,
      y: 152,
      width: statWidth,
      height: 66,
      value: fmtCompact(members.length),
      label: 'THREADS',
    });
    drawStat(ctx, {
      x: 44 + statWidth + 8,
      y: 152,
      width: statWidth,
      height: 66,
      value: fmtCompact(members.reduce((sum, thread) => sum + thread.messageCount, 0)),
      label: 'MESSAGES',
    });
    drawStat(ctx, {
      x: 44 + (statWidth + 8) * 2,
      y: 152,
      width: statWidth,
      height: 66,
      value: members.some((thread) => thread.hasCostData)
        ? fmtMoney(members.reduce((sum, thread) => sum + thread.totalCost, 0))
        : fmtCompact(members.reduce((sum, thread) => sum + thread.characterCount, 0)),
      label: members.some((thread) => thread.hasCostData) ? 'REPORTED SPEND' : 'CHARACTERS',
    });

    drawDivider(ctx, 44, 240, PANEL_W - 88);
    drawText(ctx, node.kind === 'tag' ? 'THREADS BEHIND THIS TAG' : 'THREADS IN THIS CONSTELLATION', 44, 254, {
      size: 11,
      color: HUD.muted,
      family: FONT_MONO,
      spacing: '2px',
    });

    const sorted = [...members].sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 9);
    let rowY = 278;
    for (const thread of sorted) {
      const provider = providerMeta(thread.provider);
      const nodeID = `thread:${thread.id}`;
      const hovered = panel.hoverId === `select:${nodeID}`;
      ctx.fillStyle = hovered ? 'rgba(95,227,255,0.10)' : 'rgba(255,255,255,0.02)';
      ctx.beginPath();
      ctx.roundRect(44, rowY, PANEL_W - 88, 38, 8);
      ctx.fill();
      ctx.fillStyle = provider.color;
      ctx.beginPath();
      ctx.arc(62, rowY + 19, 4, 0, Math.PI * 2);
      ctx.fill();
      drawText(ctx, truncate(thread.title, 70), 78, rowY + 19, {
        size: 15,
        color: hovered ? HUD.text : HUD.textSoft,
        family: FONT_MONO,
        baseline: 'middle',
      });
      drawText(ctx, `${fmtDate(thread.updatedAt)} · ${fmtCount(thread.messageCount, 'MSG', 'MSGS')}`, PANEL_W - 60, rowY + 19, {
        size: 11,
        color: HUD.muted,
        family: FONT_MONO,
        align: 'right',
        baseline: 'middle',
        spacing: '0.5px',
      });
      panel.addHitArea(`select:${nodeID}`, 44, rowY, PANEL_W - 88, 38);
      rowY += 44;
    }
    if (!sorted.length) {
      drawText(ctx, 'NO THREADS IN THIS VIEW', 44, 288, { size: 13, color: HUD.muted, family: FONT_MONO, spacing: '1px' });
    }

    const footerY = PANEL_H - 92;
    drawDivider(ctx, 44, footerY - 18, PANEL_W - 88);
    drawButton(panel, ctx, {
      id: 'action:clear',
      label: 'SHOW ALL',
      x: 44,
      y: footerY,
      width: 200,
      height: 48,
      size: 13,
    });
    drawButton(panel, ctx, {
      id: 'action:close',
      label: 'CLOSE',
      x: PANEL_W - 44 - 190,
      y: footerY,
      width: 190,
      height: 48,
      size: 13,
    });
    drawText(ctx, `${fmtCount(stats.tagCount, 'TAG', 'TAGS')} · ${fmtCount(stats.threadCount, 'THREAD', 'THREADS')} VISIBLE`, 300, footerY + 24, {
      size: 11,
      color: HUD.dim,
      family: FONT_MONO,
      baseline: 'middle',
      spacing: '0.8px',
    });
  });
  return panel;
}

// ------------------------------------------------------------------ help

export function createHelpPanel() {
  const panel = new WorldPanel({ width: 1.06, height: 0.795, name: 'help-panel' });
  panel.setRenderer((ctx) => {
    drawBackdrop(ctx, PANEL_W, PANEL_H, { title: 'MINDME // GUIDE', accent: HUD.lime });
    headerTitle(ctx, 'SPATIAL FIELD GUIDE', 'POINT · SELECT · INSPECT', { accent: HUD.lime });

    const rows = [
      ['POINT', 'Aim a controller or hand at the constellation. The ray shows what is selectable.'],
      ['SELECT', 'Press the trigger (or pinch) on a hub, conversation, or tag to focus it.'],
      ['INSPECT', 'A thread opens its transcript. Page with PREV / NEXT. Tags isolate their threads.'],
      ['MOVE', 'Left stick walks. Right stick turns in 30° snaps. Right stick up/down scales the map.'],
      ['RECENTER', 'A / X puts the map and panels in front of you again.'],
    ];
    let y = 156;
    for (const [key, copy] of rows) {
      drawText(ctx, key, 44, y + 2, { size: 14, color: HUD.lime, family: FONT_MONO, spacing: '1.5px' });
      y = drawWrapped(ctx, copy, 184, y, PANEL_W - 228, {
        size: 17.5,
        lineHeight: 25,
        color: HUD.textSoft,
      });
      y += 12;
    }

    drawDivider(ctx, 44, y + 6, PANEL_W - 88);
    y += 26;
    drawText(ctx, 'YOUR LIBRARY', 44, y, { size: 12, color: HUD.accent, family: FONT_MONO, spacing: '2.5px' });
    y = drawWrapped(
      ctx,
      'On the Mac, use File → Export Library for Quest. In the Quest Browser, press LOAD JSON before entering VR. The file is parsed here and stored in this headset’s browser storage; nothing is uploaded.',
      44,
      y + 24,
      PANEL_W - 88,
      { size: 17, lineHeight: 24, color: HUD.textSoft },
    );
    y = drawWrapped(
      ctx,
      'The demo archive ships with the app. Region grouping, the word-cloud lenses, and topic reclassification stay on the macOS build.',
      44,
      y + 10,
      PANEL_W - 88,
      { size: 17, lineHeight: 24, color: HUD.muted },
    );

    drawButton(panel, ctx, {
      id: 'action:help-close',
      label: 'RETURN TO THE MAP',
      x: 44,
      y: PANEL_H - 92,
      width: 280,
      height: 48,
      tone: HUD.lime,
      size: 13,
    });
    drawText(ctx, 'CREATE · 403ACCESS · MINDME', PANEL_W - 44, PANEL_H - 68, {
      size: 10,
      color: HUD.dim,
      family: FONT_MONO,
      align: 'right',
      spacing: '1.5px',
    });
  });
  return panel;
}

// ----------------------------------------------------------------- empty

export function createEmptyPanel(app) {
  const panel = new WorldPanel({ width: 0.9, height: 0.5, name: 'empty-panel' });
  panel.setRenderer((ctx) => {
    drawBackdrop(ctx, PANEL_W, PANEL_H, { title: 'MINDME // NO SIGNAL' });
    drawText(ctx, 'NO SIGNAL', 44, 120, { size: 56, color: HUD.text, weight: 700 });
    drawWrapped(
      ctx,
      'Every conversation is filtered out of this view. Bring back all sources and the full time window to see the constellation again.',
      44,
      210,
      PANEL_W - 88,
      { size: 19, lineHeight: 28, color: HUD.textSoft },
    );
    drawButton(panel, ctx, {
      id: 'action:showall',
      label: 'SHOW ALL THREADS',
      x: 44,
      y: PANEL_H - 160,
      width: 320,
      height: 54,
      active: true,
      size: 14,
    });
    drawButton(panel, ctx, {
      id: 'action:help',
      label: 'OPEN THE GUIDE',
      x: 384,
      y: PANEL_H - 160,
      width: 260,
      height: 54,
      size: 14,
    });
  });
  return panel;
}

// ---------------------------------------------------------------- manager

export class Panels {
  constructor(app, scene) {
    this.app = app;
    this.scene = scene;
    this.enabled = false;

    this.control = createControlPanel(app);
    this.help = createHelpPanel();
    this.empty = createEmptyPanel(app);
    this.inspectorState = { nodeID: null, page: 0, cache: null };
    this.inspector = createInspectorPanel(app, this.inspectorState);
    this.helpOpen = false;

    for (const panel of [this.control, this.help, this.empty, this.inspector]) {
      panel.mesh.position.set(0, -100, 0);
      scene.add(panel.mesh);
    }

    this._head = new THREE.Vector3();
    this._forward = new THREE.Vector3();
  }

  setEnabled(enabled) {
    this.enabled = enabled;
    if (!enabled) {
      for (const panel of [this.control, this.help, this.empty, this.inspector]) panel.setVisible(false);
      this.helpOpen = false;
      return;
    }
    // First immersive launch: open the field guide once per browser.
    try {
      if (!localStorage.getItem('mindme-spatial-guide-seen')) {
        this.helpOpen = true;
        localStorage.setItem('mindme-spatial-guide-seen', '1');
      }
    } catch {
      // Storage can be disabled; the guide is optional.
    }
    this.refresh();
    this.updateVisibility();
  }

  refresh() {
    this.control.invalidate();
    this.help.invalidate();
    this.empty.invalidate();
    this.inspector.invalidate();
    this.updateVisibility();
    for (const panel of [this.control, this.help, this.empty, this.inspector]) {
      if (panel.mesh.visible) panel.draw(true);
    }
  }

  setSelection(nodeID) {
    const opening = Boolean(nodeID) && !this.inspectorState.nodeID;
    if (this.inspectorState.nodeID !== nodeID) {
      this.inspectorState.nodeID = nodeID;
      this.inspectorState.page = 0;
      this.inspectorState.cache = null;
    }
    if (opening && this.enabled) this.placeInspectorNearHead();
    this.inspector.invalidate();
    this.updateVisibility();
    if (this.inspector.mesh.visible) this.inspector.draw(true);
  }

  /** Opens the inspector in a comfortable spot in front of the headset. */
  placeInspectorNearHead() {
    const camera = this.app.view?.camera;
    if (!camera) return;
    camera.getWorldPosition(this._head);
    camera.getWorldDirection(this._forward);
    const yaw = Math.atan2(this._forward.x, -this._forward.z);
    const eye = this._head.y || 1.6;
    this.inspector.placeInFrontOf(this._head, yaw, {
      distance: 1.42,
      lateral: 0.46,
      height: Math.max(1.15, Math.min(1.6, eye - 0.08)),
    });
  }

  updateVisibility() {
    if (!this.enabled) return;
    const empty = this.app.graph?.isEmpty ?? true;
    this.control.setVisible(!empty && !this.helpOpen);
    this.empty.setVisible(empty && !this.helpOpen);
    this.inspector.setVisible(Boolean(this.inspectorState.nodeID) && !this.helpOpen);
    this.help.setVisible(this.helpOpen);
  }

  placeForXR(camera) {
    if (!this.enabled) return;
    camera.getWorldPosition(this._head);
    camera.getWorldDirection(this._forward);
    const yaw = Math.atan2(this._forward.x, -this._forward.z);
    const eye = this._head.y || 1.6;

    this.control.placeInFrontOf(this._head, yaw, {
      distance: 1.45,
      lateral: -0.74,
      height: Math.max(0.95, Math.min(1.3, eye - 0.42)),
    });
    this.inspector.placeInFrontOf(this._head, yaw, {
      distance: 1.5,
      lateral: 0.5,
      height: Math.max(1.15, Math.min(1.6, eye - 0.08)),
    });
    this.empty.placeInFrontOf(this._head, yaw, {
      distance: 1.4,
      lateral: 0,
      height: Math.max(1.1, Math.min(1.55, eye - 0.1)),
    });
    this.help.placeInFrontOf(this._head, yaw, {
      distance: 1.45,
      lateral: 0,
      height: Math.max(1.15, Math.min(1.6, eye - 0.03)),
    });
    for (const panel of [this.control, this.help, this.empty, this.inspector]) {
      panel.draw(true);
    }
  }

  pick(raycaster) {
    if (!this.enabled) return null;
    let best = null;
    for (const panel of [this.control, this.help, this.empty, this.inspector]) {
      if (!panel.mesh.visible) continue;
      const hit = panel.pick(raycaster);
      if (!hit) continue;
      const distance = raycaster.ray.origin.distanceTo(hit.point);
      if (!best || distance < best.distance) best = { panel, hit, distance };
    }
    return best;
  }

  clearHover() {
    for (const panel of [this.control, this.help, this.empty, this.inspector]) panel.setHover(null);
  }

  handleAction(id) {
    if (!id) return false;
    const app = this.app;

    if (id.startsWith('group:')) {
      app.setGrouping(id.slice(6));
      return true;
    }
    if (id.startsWith('provider:')) {
      app.toggleProvider(id.slice(9));
      return true;
    }
    if (id.startsWith('window:')) {
      app.setTimeWindow(id.slice(7));
      return true;
    }
    if (id.startsWith('toggle:')) {
      app.toggleFlag(id.slice(7));
      return true;
    }
    if (id.startsWith('select:')) {
      app.select(id.slice(7));
      return true;
    }
    if (id.startsWith('focus:')) {
      app.select(id.slice(6));
      return true;
    }
    if (id === 'action:fit') {
      app.fit();
      return true;
    }
    if (id === 'action:clear') {
      app.clearFocus();
      return true;
    }
    if (id === 'action:recenter') {
      app.recenter();
      return true;
    }
    if (id === 'action:help') {
      this.helpOpen = true;
      this.updateVisibility();
      this.refresh();
      return true;
    }
    if (id === 'action:help-close') {
      this.helpOpen = false;
      this.updateVisibility();
      this.refresh();
      return true;
    }
    if (id === 'action:close') {
      app.deselect();
      return true;
    }
    if (id === 'action:prev') {
      this.inspectorState.page = Math.max(0, this.inspectorState.page - 1);
      this.inspector.invalidate();
      this.inspector.draw(true);
      return true;
    }
    if (id === 'action:next') {
      this.inspectorState.page += 1;
      this.inspector.invalidate();
      this.inspector.draw(true);
      return true;
    }
    if (id === 'action:showall') {
      app.showAll();
      return true;
    }
    return false;
  }

  update(dt, camera) {
    if (!this.enabled) return;
    for (const panel of [this.control, this.help, this.empty, this.inspector]) {
      if (!panel.mesh.visible) continue;
      panel.faceCamera(camera, dt);
      panel.draw();
    }
  }
}
