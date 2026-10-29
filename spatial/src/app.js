// Application state: library, filters, selection, and the link between the
// 3D view, the VR panels, and the flat DOM HUD.

import demoRaw from './data/demo-library.json';
import { buildGraph, defaultFilters, resolveTimeWindow, summarizeGraph } from './data/graph.js';
import { libraryStats, normalizeLibrary } from './data/library.js';
import { clearLibraryJSON, loadLibraryJSON, saveLibraryJSON } from './storage.js';
import { Emitter } from './util.js';

export class App extends Emitter {
  constructor() {
    super();
    this.library = null;
    this.libraryStats = null;
    this.graph = null;
    this.filters = defaultFilters();
    this.timeWindow = 'all';
    this.selectedNodeId = null;
    this.source = 'demo';
    this.sourceLabel = 'DEMO ARCHIVE';
    this.view = null;
    this.hud = null;
    this.xr = null;
    this.isVR = false;
    this.searchDebounce = null;
  }

  attach({ view, hud, xr }) {
    this.view = view;
    this.hud = hud;
    this.xr = xr;
  }

  // ---------------------------------------------------------------- boot

  async start() {
    const params = new URLSearchParams(location.search);
    const demoForced = params.has('demo');
    const libraryURL = params.get('library');

    // An explicit library URL wins even when ?demo=1 is also present.
    if (libraryURL) {
      try {
        const response = await fetch(libraryURL);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const text = await response.text();
        this.setLibrary(normalizeLibrary(text), { source: 'url', label: libraryURL, persist: false });
      } catch (error) {
        this.toast(`Could not load ${libraryURL}: ${error.message}`, 'error');
      }
    }

    if (!this.library && !demoForced) {
      try {
        const record = await loadLibraryJSON();
        if (record?.json) {
          this.setLibrary(normalizeLibrary(record.json), {
            source: 'stored',
            label: record.name ? `STORED · ${record.name}` : 'STORED LIBRARY',
            persist: false,
          });
        }
      } catch (error) {
        console.warn('[mindme] stored library unavailable', error);
      }
    }

    if (!this.library) {
      this.loadDemo({ silent: true });
    }

    this.emit('ready', this);
  }

  loadDemo({ silent = false } = {}) {
    const library = normalizeLibrary(demoRaw);
    freshenDemoDates(library);
    this.setLibrary(library, { source: 'demo', label: 'DEMO ARCHIVE', persist: false });
    if (!silent) this.toast('Demo archive loaded.', 'success');
  }

  // ------------------------------------------------------------ library

  setLibrary(library, { source = 'import', label = null, persist = false, name = null } = {}) {
    this.library = library;
    this.libraryStats = libraryStats(library);
    this.graph = null;
    this.source = source;
    this.sourceLabel =
      label ?? (source === 'demo' ? 'DEMO ARCHIVE' : source === 'url' ? 'LIBRARY URL' : 'LOCAL LIBRARY');
    this.selectedNodeId = null;

    if (persist) {
      saveLibraryJSON(JSON.stringify({ threads: library.threads, lastImport: library.lastImport }), {
        name,
      }).catch((error) => {
        console.warn('[mindme] could not persist library', error);
        this.toast('Loaded, but this browser could not store the library for next time.', 'error');
      });
    }

    this.emit('library', { library, source: this.source, label: this.sourceLabel });
    this.rebuild();
  }

  async importText(text, name = null) {
    try {
      const library = normalizeLibrary(text);
      this.setLibrary(library, {
        source: 'import',
        label: name ? `LOCAL · ${name}` : 'LOCAL LIBRARY',
        persist: true,
        name,
      });
      this.toast(
        `Loaded ${library.threads.length} conversations from ${name ?? 'the library'}.`,
        'success',
      );
      this.hud?.hideLaunch();
      this.hud?.setGuideVisible(false);
      return true;
    } catch (error) {
      this.toast(error.message, 'error');
      return false;
    }
  }

  async clearStoredLibrary() {
    try {
      await clearLibraryJSON();
    } catch (error) {
      console.warn('[mindme] clear failed', error);
    }
    this.loadDemo();
    this.toast('Stored library cleared. Demo archive restored.', 'info');
  }

  // ------------------------------------------------------------- graph

  rebuild() {
    if (!this.library) return;
    const previousSelection = this.selectedNodeId;
    const firstGraph = !this.graph;
    this.graph = buildGraph(this.library, this.filters);

    if (previousSelection && !this.graph.nodes.some((node) => node.id === previousSelection)) {
      this.selectedNodeId = null;
    }

    this.view?.setGraph(this.graph, { selected: this.selectedNodeId, fit: firstGraph });
    this.view?.panels?.refresh();
    this.view?.panels?.setSelection(this.selectedNodeId);
    this.hud?.render();
    this.emit('graph', this.graph);
    this.emit('selection', this.selectedNodeId);
  }

  toggleProvider(providerID) {
    if (this.filters.providers.has(providerID)) this.filters.providers.delete(providerID);
    else this.filters.providers.add(providerID);
    this.selectedNodeId = null;
    this.rebuild();
  }

  setGrouping(mode) {
    if (this.filters.grouping === mode) return;
    this.filters.grouping = mode;
    this.rebuild();
  }

  setTimeWindow(id) {
    if (this.timeWindow === id) return;
    this.timeWindow = id;
    this.filters.since = resolveTimeWindow(id);
    this.rebuild();
  }

  setSearch(text) {
    this.filters.searchText = text;
    if (this.searchDebounce) clearTimeout(this.searchDebounce);
    this.searchDebounce = setTimeout(() => {
      this.searchDebounce = null;
      this.rebuild();
    }, 180);
  }

  toggleFlag(flag) {
    if (flag === 'tags') {
      this.filters.includeTags = !this.filters.includeTags;
      this.rebuild();
      return;
    }
    if (flag === 'labels') {
      this.filters.showLabels = !this.filters.showLabels;
      this.view?.constellation.setLabels(this.filters.showLabels);
      this.view?.panels?.refresh();
      this.hud?.render();
      return;
    }
    if (flag === 'motion') {
      this.filters.motion = !this.filters.motion;
      this.view?.setMotion(this.filters.motion);
      this.view?.panels?.refresh();
      this.hud?.render();
      return;
    }
    if (flag === 'spend') {
      if (!this.filters.spend && !(this.graph?.stats.costThreadCount > 0)) {
        this.toast('No provider-reported costs in this library. Import an OpenCode archive to use spend heat.', 'info');
        return;
      }
      this.filters.spend = !this.filters.spend;
      this.view?.constellation.setSpend(this.filters.spend);
      this.view?.panels?.refresh();
      this.hud?.render();
    }
  }

  showAll() {
    this.filters.providers = new Set(['chatgpt', 'gemini', 'claude', 'opencode', 'other']);
    this.filters.since = null;
    this.filters.searchText = '';
    this.timeWindow = 'all';
    this.selectedNodeId = null;
    this.hud?.syncSearchInput(true);
    this.rebuild();
    this.toast('All threads restored.', 'info');
  }

  // --------------------------------------------------------- selection

  select(nodeID) {
    if (!nodeID) return;
    if (!this.graph?.nodes.some((node) => node.id === nodeID)) return;
    this.selectedNodeId = nodeID;
    this.view?.constellation.setFocus(nodeID);
    this.view?.panels?.setSelection(nodeID);
    this.hud?.renderSelection();
    this.emit('selection', nodeID);
    this.xr?.pulse();
  }

  deselect() {
    if (!this.selectedNodeId) return;
    this.selectedNodeId = null;
    this.view?.constellation.setFocus(null);
    this.view?.panels?.setSelection(null);
    this.hud?.renderSelection();
    this.emit('selection', null);
  }

  clearFocus() {
    this.deselect();
  }

  // --------------------------------------------------------------- view

  fit() {
    this.view?.fit();
  }

  recenter() {
    if (this.isVR) this.view?.recenterXR();
    else this.view?.fit();
  }

  setVR(active) {
    this.isVR = active;
    document.body.classList.toggle('in-xr', active);
    this.view?.panels?.setEnabled(active);
    if (active) {
      this.hud?.hideLaunch();
      this.hud?.setGuideVisible(false);
      document.getElementById('file-input')?.blur();
    }
    this.hud?.render();
    this.emit('vr', active);
  }

  toast(text, kind = 'info') {
    this.hud?.toast(text, kind);
    this.emit('toast', { text, kind });
  }

  summary() {
    return this.graph ? summarizeGraph(this.graph) : 'NO SIGNAL';
  }

  node() {
    return this.graph?.nodes.find((node) => node.id === this.selectedNodeId) ?? null;
  }

  threadForNode(node) {
    if (!node) return null;
    if (node.threadID) return this.library?.threads.find((thread) => thread.id === node.threadID) ?? null;
    return null;
  }
}

/**
 * The demo ships with fixed ISO dates so it stays reproducible, but a static
 * archive would age out of the 30-day window. Shift the whole timeline so the
 * newest conversation is today.
 */
function freshenDemoDates(library) {
  const latest = library.threads.reduce(
    (max, thread) => (!max || thread.updatedAt > max ? thread.updatedAt : max),
    null,
  );
  if (!latest) return;
  const delta = Date.now() - latest.getTime();
  if (Math.abs(delta) < 60_000) return;
  const shift = (date) => (date ? new Date(date.getTime() + delta) : date);
  for (const thread of library.threads) {
    thread.createdAt = shift(thread.createdAt);
    thread.updatedAt = shift(thread.updatedAt);
    for (const message of thread.messages) message.timestamp = shift(message.timestamp);
  }
}
