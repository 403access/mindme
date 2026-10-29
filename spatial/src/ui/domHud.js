// Flat DOM HUD: launch card, stats, filters, help, and the desktop inspector.
// In VR the same state is rendered by the world-space panels instead.

import { GROUPINGS, TIME_WINDOWS, summarizeGraph } from '../data/graph.js';
import { prettyLabel } from '../data/keywords.js';
import { PROVIDERS, providerMeta } from '../theme.js';
import {
  escapeHtml,
  fmtCompact,
  fmtCount,
  fmtDate,
  fmtDateTime,
  fmtMoney,
  truncate,
} from '../util.js';

const $ = (id) => document.getElementById(id);

function roleLabel(role) {
  return { user: 'YOU', assistant: 'ASSISTANT', system: 'SYSTEM', tool: 'TOOL' }[role] ?? String(role).toUpperCase();
}

export class DomHud {
  constructor(app) {
    this.app = app;
    this.toastTimer = null;
    this.vrButtons = [$('btn-vr'), $('btn-launch-vr')].filter(Boolean);
    this.fileInput = $('file-input');
    this.launch = $('launch');
    this.guide = $('launch-guide');
    this.inspector = $('inspector');
    this.toastEl = $('toast');
    this.dropHint = $('drop-hint');
    this.searchInput = $('search-input');
    this.vrSupportChecked = false;

    this._bind();

    app.on('graph', () => this.render());
    app.on('library', () => this.render());
    app.on('selection', () => this.renderSelection());
    app.on('vr', (active) => {
      if (!active) this.render();
    });
  }

  init() {
    this.render();
    this._checkVRSupport();
    this.playLaunchIntro();
  }

  // ---------------------------------------------------------------- bind

  _bind() {
    $('btn-load')?.addEventListener('click', () => this.fileInput?.click());
    $('btn-launch-load')?.addEventListener('click', () => this.fileInput?.click());
    $('btn-explore')?.addEventListener('click', () => this.hideLaunch());
    $('btn-help')?.addEventListener('click', () => this.toggleGuide());
    $('btn-launch-vr')?.addEventListener('click', () => this.app.xr?.enter());
    $('btn-vr')?.addEventListener('click', () => this.app.xr?.enter());
    $('inspector-close')?.addEventListener('click', () => this.app.deselect());

    this.fileInput?.addEventListener('change', async () => {
      const file = this.fileInput.files?.[0];
      this.fileInput.value = '';
      if (!file) return;
      const text = await file.text();
      this.app.importText(text, file.name);
    });

    this.searchInput?.addEventListener('input', () => this.app.setSearch(this.searchInput.value));

    // Delegated clicks for dynamically rendered filter chips and rows.
    $('filters')?.addEventListener('click', (event) => {
      const chip = event.target.closest('[data-action]');
      if (!chip) return;
      const action = chip.dataset.action;
      const value = chip.dataset.value;
      if (action === 'provider') this.app.toggleProvider(value);
      if (action === 'grouping') this.app.setGrouping(value);
      if (action === 'window') this.app.setTimeWindow(value);
      if (action === 'flag') this.app.toggleFlag(value);
    });

    this.inspector?.addEventListener('click', (event) => {
      const focus = event.target.closest('[data-focus]');
      if (focus) {
        this.app.select(focus.dataset.focus);
        return;
      }
      const row = event.target.closest('[data-node]');
      if (row) this.app.select(row.dataset.node);
    });

    $('btn-clear-storage')?.addEventListener('click', async () => {
      if (!window.confirm('Clear the library stored in this browser and restore the demo archive?')) return;
      await this.app.clearStoredLibrary();
      this.render();
    });

    // Drag & drop anywhere on the window.
    let dragDepth = 0;
    window.addEventListener('dragenter', (event) => {
      if (!event.dataTransfer?.types?.includes('Files')) return;
      dragDepth += 1;
      this.dropHint?.classList.remove('hidden');
    });
    window.addEventListener('dragleave', () => {
      dragDepth = Math.max(0, dragDepth - 1);
      if (!dragDepth) this.dropHint?.classList.add('hidden');
    });
    window.addEventListener('dragover', (event) => {
      if (event.dataTransfer?.types?.includes('Files')) event.preventDefault();
    });
    window.addEventListener('drop', async (event) => {
      event.preventDefault();
      dragDepth = 0;
      this.dropHint?.classList.add('hidden');
      const file = event.dataTransfer?.files?.[0];
      if (!file) return;
      const text = await file.text();
      this.app.importText(text, file.name);
    });
  }

  async _checkVRSupport() {
    if (this.vrSupportChecked || !this.app.xr) return;
    this.vrSupportChecked = true;
    const supported = await this.app.xr.isSupported();
    if (!supported) {
      for (const button of this.vrButtons) {
        button.disabled = true;
        button.title = 'Immersive WebXR is not available in this browser. Open this page in the Meta Quest Browser.';
        button.textContent = 'VR UNAVAILABLE';
      }
      const note = $('launch-note');
      if (note) {
        note.innerHTML =
          'WebXR is not detected in this browser. The flat view still works; for the spatial experience, open this page in the <strong>Meta Quest Browser</strong> on your headset.';
      }
    }
  }

  // -------------------------------------------------------------- launch

  playLaunchIntro() {
    this.launch?.classList.remove('hidden');
  }

  hideLaunch() {
    this.launch?.classList.add('hidden');
  }

  showLaunch() {
    this.launch?.classList.remove('hidden');
  }

  setGuideVisible(visible) {
    this.guide?.classList.toggle('hidden', !visible);
  }

  toggleGuide() {
    const visible = this.launch?.classList.contains('hidden') ?? true;
    if (visible) this.showLaunch();
    const guideOpen = !this.guide?.classList.contains('hidden');
    this.setGuideVisible(!guideOpen);
  }

  // -------------------------------------------------------------- render

  render() {
    if (!this.app.graph) return;

    const stats = this.app.graph.stats;
    const libraryStats = this.app.libraryStats;
    const source = this.app.sourceLabel;

    const topbar = $('topbar-stats');
    if (topbar) {
      const providers = PROVIDERS.filter((provider) => stats && this.app.library?.threads.some((thread) => thread.provider === provider.id))
        .map((provider) => provider.short)
        .join(' · ');
      topbar.textContent = `${source}  ·  ${summarizeGraph(this.app.graph)}${providers ? `  ·  ${providers}` : ''}`;
    }

    const launchStats = $('launch-stats');
    if (launchStats) {
      const parts = [
        fmtCount(libraryStats?.threads ?? 0, 'CONVERSATION', 'CONVERSATIONS'),
        fmtCount(libraryStats?.messages ?? 0, 'MESSAGE', 'MESSAGES'),
        fmtCount(libraryStats?.providers ?? 0, 'SOURCE', 'SOURCES'),
      ];
      if (libraryStats?.costThreads) parts.push(`${fmtMoney(libraryStats.totalCost)} REPORTED SPEND`);
      else if (libraryStats?.characters) parts.push(`${fmtCompact(libraryStats.characters)} CHARACTERS`);
      launchStats.textContent = parts.join('   ·   ');
    }

    this._renderFilters();
    this._renderInspector();
    this.syncSearchInput();
  }

  _renderFilters() {
    const providerHost = $('provider-filters');
    if (providerHost) {
      providerHost.innerHTML = PROVIDERS.map((provider) => {
        const count = this.app.library?.threads.filter((thread) => thread.provider === provider.id).length ?? 0;
        const active = this.app.filters.providers.has(provider.id);
        return `<button type="button" class="chip ${active ? 'on' : 'off'}" data-action="provider" data-value="${provider.id}" style="--chip-color:${provider.color}">
          <span class="dot" style="color:${provider.color}"></span>${escapeHtml(provider.short)} ${count}
        </button>`;
      }).join('');
    }

    const groupingHost = $('grouping-filters');
    if (groupingHost) {
      groupingHost.innerHTML = GROUPINGS.map(
        (mode) =>
          `<button type="button" class="chip accent ${this.app.filters.grouping === mode.id ? 'on' : ''}" data-action="grouping" data-value="${mode.id}">${mode.label}</button>`,
      ).join('');
    }

    const windowHost = $('window-filters');
    if (windowHost) {
      windowHost.innerHTML = TIME_WINDOWS.map(
        (window) =>
          `<button type="button" class="chip ${this.app.timeWindow === window.id ? 'on' : ''}" data-action="window" data-value="${window.id}">${window.label}</button>`,
      ).join('');
    }

    const viewHost = $('view-filters');
    if (viewHost) {
      const spendAvailable = Boolean(this.app.graph?.stats.costThreadCount);
      const flags = [
        ['tags', 'TAGS', this.app.filters.includeTags],
        ['labels', 'LABELS', this.app.filters.showLabels],
        ['motion', 'MOTION', this.app.filters.motion],
        ['spend', 'COST', this.app.filters.spend],
      ];
      viewHost.innerHTML = flags
        .map(
          ([id, label, active]) =>
            `<button type="button" class="chip ${active ? 'on' : ''} ${id === 'spend' && !spendAvailable ? 'off' : ''}" data-action="flag" data-value="${id}" title="${id === 'spend' && !spendAvailable ? 'No provider-reported cost data in this library' : ''}">${label}</button>`,
        )
        .join('');
    }
  }

  syncSearchInput(force = false) {
    if (!this.searchInput) return;
    if (!force && document.activeElement === this.searchInput) return;
    this.searchInput.value = this.app.filters.searchText ?? '';
  }

  // ----------------------------------------------------------- inspector

  _renderInspector() {
    if (!this.inspector) return;
    const node = this.app.node();
    const body = $('inspector-body');
    if (!node || !body) {
      this.inspector.classList.add('hidden');
      return;
    }
    this.inspector.classList.remove('hidden');

    if (node.kind === 'thread') {
      const thread = this.app.threadForNode(node);
      const provider = providerMeta(thread?.provider ?? 'other');
      const tags = this.app.graph.keywordsByThread.get(node.threadID) ?? [];
      const messages = thread?.messages ?? [];
      const sourceURL = /^https?:\/\//i.test(thread?.sourceURL ?? '') ? thread.sourceURL : null;

      body.innerHTML = `
        <div class="kicker" style="color:${provider.color}">THREAD · ${escapeHtml(provider.name.toUpperCase())}</div>
        <h2>${escapeHtml(thread?.title ?? node.label)}</h2>
        <div class="meta">
          ${escapeHtml(thread?.model ?? provider.name)}<br />
          ${thread ? `${fmtDate(thread.createdAt)} → ${fmtDate(thread.updatedAt)}` : ''}<br />
          ${thread?.sourceFile ? `SOURCE · ${escapeHtml(thread.sourceFile)}` : ''}
          ${sourceURL ? `<br /><a href="${escapeHtml(sourceURL)}" target="_blank" rel="noopener noreferrer">OPEN ORIGINAL ↗</a>` : ''}
        </div>
        <div class="stat-row">
          <div class="stat"><div class="value">${fmtCompact(thread?.messageCount ?? 0)}</div><div class="label">MESSAGES</div></div>
          <div class="stat"><div class="value">${thread?.hasCostData ? fmtMoney(thread.totalCost) : fmtCompact(thread?.wordCount ?? 0)}</div><div class="label">${thread?.hasCostData ? 'SPEND' : 'WORDS'}</div></div>
          <div class="stat"><div class="value">${fmtCompact(thread?.characterCount ?? 0)}</div><div class="label">CHARACTERS</div></div>
        </div>
        <div class="tag-row">
          ${tags
            .slice(0, 12)
            .map((tag) => {
              const tagNode = this.app.graph.nodes.find((item) => item.kind === 'tag' && item.tag === tag.term);
              return tagNode
                ? `<button type="button" class="tag-chip" data-focus="${tagNode.id}">${escapeHtml(prettyLabel(tag.term))}</button>`
                : `<span class="tag-chip muted">${escapeHtml(prettyLabel(tag.term))}</span>`;
            })
            .join('')}
        </div>
        <div class="divider"></div>
        <div class="status-line">TRANSCRIPT · ${fmtCount(messages.length, 'MESSAGE', 'MESSAGES')}</div>
        <div class="transcript">
          ${
            messages.length
              ? messages
                  .map(
                    (message) => `
              <div class="message ${message.role}">
                <div class="role">${roleLabel(message.role)}${message.timestamp ? ` · ${fmtDateTime(message.timestamp)}` : ''}${message.cost != null ? ` · ${fmtMoney(message.cost)}` : ''}</div>
                <p>${escapeHtml(message.text)}</p>
              </div>`,
                  )
                  .join('')
              : '<div class="transcript-empty">No transcript available.</div>'
          }
        </div>
      `;
      return;
    }

    const members = this._memberThreads(node);
    const stats = this.app.graph.stats;
    const kicker =
      node.kind === 'group' ? 'CONSTELLATION' : node.kind === 'tag' ? 'SHARED KEYWORD' : 'ROOT';
    const title = node.label;
    const providers = [...new Set(members.map((thread) => thread.provider))];

    body.innerHTML = `
      <div class="kicker">${kicker}</div>
      <h2>${escapeHtml(title)}</h2>
      <div class="meta">
        ${escapeHtml(node.subtitle ?? '')}<br />
        ${providers.map((id) => escapeHtml(providerMeta(id).name.toUpperCase())).join(' · ')}
      </div>
      <div class="stat-row">
        <div class="stat"><div class="value">${fmtCompact(members.length)}</div><div class="label">THREADS</div></div>
        <div class="stat"><div class="value">${fmtCompact(members.reduce((sum, thread) => sum + thread.messageCount, 0))}</div><div class="label">MESSAGES</div></div>
        <div class="stat"><div class="value">${
          members.some((thread) => thread.hasCostData)
            ? fmtMoney(members.reduce((sum, thread) => sum + thread.totalCost, 0))
            : fmtCompact(members.reduce((sum, thread) => sum + thread.characterCount, 0))
        }</div><div class="label">${members.some((thread) => thread.hasCostData) ? 'SPEND' : 'CHARACTERS'}</div></div>
      </div>
      <div class="status-line">${node.kind === 'tag' ? 'THREADS BEHIND THIS TAG' : 'THREADS IN THIS CONSTELLATION'} · ${fmtCount(members.length, 'THREAD', 'THREADS')}</div>
      <div class="thread-list">
        ${[...members]
          .sort((a, b) => b.updatedAt - a.updatedAt)
          .slice(0, 40)
          .map((thread) => {
            const provider = providerMeta(thread.provider);
            return `<button type="button" class="thread-row" data-node="thread:${escapeHtml(thread.id)}">
              <span class="dot" style="background:${provider.color}"></span>
              <span class="title">${escapeHtml(truncate(thread.title, 64))}</span>
              <span class="meta">${fmtDate(thread.updatedAt)} · ${fmtCount(thread.messageCount, 'MSG', 'MSGS')}</span>
            </button>`;
          })
          .join('')}
      </div>
      ${members.length > 40 ? `<div class="status-line">SHOWING 40 OF ${members.length}</div>` : ''}
      <div class="divider"></div>
      <div class="status-line">${fmtCount(stats.tagCount, 'TAG', 'TAGS')} · ${fmtCount(stats.threadCount, 'THREAD', 'THREADS')} VISIBLE</div>
    `;
  }

  _memberThreads(node) {
    const graph = this.app.graph;
    if (!graph) return [];
    let ids = [];
    if (node.kind === 'group') ids = node.threadIDs ?? [];
    else if (node.kind === 'tag') ids = graph.edges.filter((edge) => edge.target === node.id).map((edge) => edge.source);
    else ids = graph.nodes.filter((item) => item.kind === 'thread').map((item) => item.id);
    const byID = new Map(this.app.library.threads.map((thread) => [thread.id, thread]));
    return ids.map((id) => byID.get(id.replace(/^thread:/, ''))).filter(Boolean);
  }

  renderSelection() {
    this._renderInspector();
  }

  // --------------------------------------------------------------- toast

  toast(text, kind = 'info') {
    if (!this.toastEl) return;
    this.toastEl.textContent = text;
    this.toastEl.className = `toast ${kind}`;
    if (this.toastTimer) clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => {
      this.toastEl.classList.add('hidden');
    }, 5200);
  }
}
