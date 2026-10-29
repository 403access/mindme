// Node-side sanity checks for the data layer. No browser needed:
//   npm run check
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { buildGraph, defaultFilters, focusPath, resolveTimeWindow } from '../src/data/graph.js';
import { libraryStats, normalizeLibrary } from '../src/data/library.js';
import { anchors3D } from '../src/data/layout3d.js';

const demo = JSON.parse(readFileSync(fileURLToPath(new URL('../src/data/demo-library.json', import.meta.url)), 'utf8'));
const library = normalizeLibrary(demo);

assert.equal(library.threads.length, 91, 'demo thread count');
const stats = libraryStats(library);
assert.equal(stats.messages, 514, 'demo message count');
assert.equal(stats.providers, 5, 'demo provider count');
assert.ok(stats.totalCost > 0, 'demo has spend data');
assert.equal(stats.costThreads, 7, 'demo OpenCode spend threads');

const filters = defaultFilters();
let graph = buildGraph(library, filters);
assert.equal(graph.stats.threadCount, 91);
assert.equal(graph.stats.groupCount, 5);
assert.equal(graph.stats.tagCount, 60);
assert.equal(graph.nodes.filter((n) => n.kind === 'thread').length, 91);

// Every edge resolves, and every tag node has at least one edge.
const ids = new Set(graph.nodes.map((n) => n.id));
for (const edge of graph.edges) {
  assert.ok(ids.has(edge.source), `missing edge source ${edge.source}`);
  assert.ok(ids.has(edge.target), `missing edge target ${edge.target}`);
}
for (const tag of graph.nodes.filter((n) => n.kind === 'tag')) {
  assert.ok(graph.edges.some((edge) => edge.source === tag.id || edge.target === tag.id), `isolated ${tag.id}`);
}

// Search is case-insensitive and hyphen-insensitive.
const search = (query) => {
  const next = { ...defaultFilters(), searchText: query };
  return buildGraph(library, next).stats.threadCount;
};
const ebike = search('ebike');
assert.ok(ebike > 0, 'hyphenated search hits');
assert.equal(search('e-bike'), ebike, 'hyphen search matches');
assert.equal(search('zzzz-no-such-thread'), 0, 'empty search result');
assert.ok(search('battery') > 0, 'search finds message text');

// Groupings.
for (const mode of ['provider', 'topic', 'era']) {
  const grouped = buildGraph(library, { ...defaultFilters(), grouping: mode });
  assert.ok(grouped.stats.groupCount > 0, `${mode} groups`);
  assert.equal(grouped.stats.threadCount, 91, `${mode} thread count`);
  assert.ok(grouped.nodes.every((node) => node.kind !== 'group' || node.threadIDs.length > 0 || mode === 'topic'));
}

// Time windows shrink the set monotonically.
const windows = ['all', 'year', 'ninety', 'thirty'].map((id) => {
  const next = { ...defaultFilters(), since: resolveTimeWindow(id) };
  return buildGraph(library, next).stats.threadCount;
});
assert.equal(windows[0], 91);
assert.ok(windows[0] >= windows[1] && windows[1] >= windows[2] && windows[2] >= windows[3]);

// Selection focus reaches the root and the surrounding group.
const threadNode = graph.nodes.find((node) => node.kind === 'thread' && node.provider === 'chatgpt');
const path = focusPath(graph, threadNode.id);
assert.ok(path.has('root'));
assert.ok(path.has(threadNode.groupID));
assert.ok(path.size >= 2);

// Deterministic 3D layout.
const a = anchors3D(graph);
const b = anchors3D(graph);
assert.equal(a.size, graph.nodes.length);
for (const [id, point] of a) {
  const other = b.get(id);
  assert.ok(other);
  assert.ok(Math.abs(point.x - other.x) < 1e-9 && Math.abs(point.y - other.y) < 1e-9 && Math.abs(point.z - other.z) < 1e-9);
}
assert.ok([...a.values()].every((point) => Number.isFinite(point.x) && Number.isFinite(point.y) && Number.isFinite(point.z)));

// Empty filter → root only.
const empty = buildGraph(library, { ...defaultFilters(), providers: new Set() });
assert.equal(empty.isEmpty, true);
assert.equal(empty.nodes.length, 1);
assert.equal(empty.nodes[0].kind, 'root');

// Generic schema, no provider, numeric timestamps.
const generic = normalizeLibrary({
  threads: [
    {
      id: 'generic-1',
      title: 'A generic thread',
      createdAt: '2026-03-01T10:00:00Z',
      messages: [
        { role: 'human', text: 'Hello there', timestamp: 1_772_000_000_000 },
        { role: 'ai', text: 'Hi. Here is a battery design.' },
      ],
    },
  ],
});
assert.equal(generic.threads.length, 1);
assert.equal(generic.threads[0].provider, 'other');
assert.equal(generic.threads[0].messages[0].role, 'user');
assert.equal(generic.threads[0].messages[1].role, 'assistant');

const genericGraph = buildGraph(generic, defaultFilters());
assert.equal(genericGraph.stats.threadCount, 1);
assert.equal(genericGraph.stats.tagCount, 0);

console.log('MINDME spatial data checks passed');
console.log(`  threads ${library.threads.length} · messages ${stats.messages} · tags ${graph.stats.tagCount} · spend $${stats.totalCost.toFixed(2)}`);
console.log(`  search "ebike" → ${ebike} · windows ${windows.join(' / ')} · layout ${a.size} anchors`);
