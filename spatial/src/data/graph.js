// Port of MindMap/Core/Sources/MindMapCore/Graph/GraphBuilder.swift and
// TopicClusterer.swift: filters, provider/topic/era constellations, and shared
// keyword tags. Region grouping stays on the Mac for now (it needs the topic
// pipeline and taxonomy cache).

import { PROVIDERS, topicColor, providerColor } from '../theme.js';
import { fmtCount, slug } from '../util.js';
import { buildIndex } from './keywords.js';

export const GROUPINGS = [
  { id: 'provider', label: 'PROVIDER' },
  { id: 'topic', label: 'TOPIC' },
  { id: 'era', label: 'ERA' },
];

export const TIME_WINDOWS = [
  { id: 'all', label: 'ALL', days: null },
  { id: 'year', label: '1Y', days: 365 },
  { id: 'ninety', label: '90D', days: 90 },
  { id: 'thirty', label: '30D', days: 30 },
];

export function defaultFilters() {
  return {
    providers: new Set(PROVIDERS.map((provider) => provider.id)),
    searchText: '',
    since: null,
    grouping: 'provider',
    includeTags: true,
    showLabels: true,
    motion: true,
    maxThreads: 420,
    spend: false,
  };
}

// Hyphens, spaces and punctuation are ignored so "ebike", "e-bike", and
// "E Bike" all find the same conversation.
const searchable = (text) =>
  String(text ?? '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^\p{L}\p{N}]+/gu, '');

export function matchesThread(thread, filters) {
  if (!filters.providers.has(thread.provider)) return false;
  if (filters.since && thread.updatedAt < filters.since) return false;
  const rawQuery = String(filters.searchText ?? '').toLowerCase();
  const query = searchable(rawQuery);
  if (!query) return true;
  const title = searchable(thread.title);
  if (title.includes(query)) return true;
  if (thread.messages.some((message) => searchable(message.text).includes(query))) return true;
  const tokens = rawQuery.split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  if (tokens.length <= 1) return false;
  const haystack = searchable(`${thread.title} ${thread.messages.map((message) => message.text).join(' ')}`);
  return tokens.every((token) => haystack.includes(searchable(token)));
}

export function threadCountLabel(count) {
  return fmtCount(count, 'THREAD', 'THREADS');
}

export function makeRootNode(count, groupCount) {
  return {
    id: 'root',
    kind: 'root',
    label: 'MINDME',
    subtitle: count === 0 ? 'NO SIGNAL' : `${threadCountLabel(count)} · ${fmtCount(groupCount, 'CONSTELLATION', 'CONSTELLATIONS')}`,
    weight: 1,
    colorSeed: 0,
    cost: 0,
    tokenCount: 0,
    provider: null,
    groupID: null,
    threadID: null,
    tag: null,
    parentID: null,
  };
}

// --------------------------------------------------------------- clusters

function buildTopicClusters(threads, index, maxTopics = 9, minimumSize = 2) {
  if (threads.length < 2) return [];

  const totals = Object.create(null);
  const keywordScoresByThread = new Map();
  const bestTermByThread = new Map();

  for (const thread of threads) {
    const keywords = index.keywordsByThread.get(thread.id) ?? [];
    const termScores = Object.create(null);
    for (const keyword of keywords) {
      termScores[keyword.term] = keyword.score;
      totals[keyword.term] = (totals[keyword.term] ?? 0) + keyword.score;
    }
    keywordScoresByThread.set(thread.id, termScores);
    if (keywords[0]) bestTermByThread.set(thread.id, keywords[0].term);
  }

  const candidates = Object.entries(totals)
    .map(([term, total]) => ({ term, total, documentFrequency: index.documentFrequency[term] ?? 0 }))
    .filter((candidate) => candidate.documentFrequency >= 2)
    .sort((a, b) => {
      const l = a.total * Math.log(a.documentFrequency + 1);
      const r = b.total * Math.log(b.documentFrequency + 1);
      if (Math.abs(l - r) > 0.001) return r - l;
      return a.term.localeCompare(b.term);
    });

  const selected = [];
  for (const candidate of candidates) {
    const dominated = selected.some(
      (existing) =>
        (existing.term.includes(candidate.term) || candidate.term.includes(existing.term)) &&
        existing.documentFrequency >= candidate.documentFrequency,
    );
    if (dominated) continue;
    selected.push(candidate);
    if (selected.length >= maxTopics) break;
  }
  if (!selected.length) return [];

  const assignment = new Map();
  for (const thread of threads) {
    const termScores = keywordScoresByThread.get(thread.id) ?? {};
    let best = null;
    for (const candidate of selected) {
      const score = termScores[candidate.term];
      if (score == null) continue;
      if (!best || score > best.score) best = { term: candidate.term, score };
    }
    if (best) {
      assignment.set(thread.id, best.term);
    } else {
      const fallback = bestTermByThread.get(thread.id);
      if (fallback && selected.some((candidate) => candidate.term === fallback)) {
        assignment.set(thread.id, fallback);
      }
    }
  }

  const build = (terms) => {
    const byTerm = new Map();
    for (const [threadID, term] of assignment) {
      if (!terms.some((candidate) => candidate.term === term)) continue;
      if (!byTerm.has(term)) byTerm.set(term, []);
      byTerm.get(term).push(threadID);
    }
    return terms
      .filter((candidate) => (byTerm.get(candidate.term)?.length ?? 0) >= minimumSize)
      .map((candidate) => ({
        id: `topic:${slug(candidate.term)}`,
        label: candidate.term,
        threadIDs: [...byTerm.get(candidate.term)].sort(),
        colorSeed: 0,
        score: candidate.total,
      }));
  };

  let working = selected;
  let clusters = build(working);

  for (let pass = 0; pass < 2; pass += 1) {
    const surviving = new Set(clusters.map((cluster) => cluster.label));
    if (surviving.size === working.length) break;
    working = working.filter((candidate) => surviving.has(candidate.term));

    for (const thread of threads) {
      const current = assignment.get(thread.id);
      if (!current || surviving.has(current)) continue;
      const termScores = keywordScoresByThread.get(thread.id) ?? {};
      let next = null;
      for (const candidate of working) {
        const score = termScores[candidate.term];
        if (score == null) continue;
        if (!next || score > next.score) next = { term: candidate.term, score };
      }
      if (next) assignment.set(thread.id, next.term);
      else assignment.delete(thread.id);
    }
    clusters = build(working);
  }

  clusters.sort((a, b) => {
    if (a.threadIDs.length !== b.threadIDs.length) return b.threadIDs.length - a.threadIDs.length;
    return a.label.localeCompare(b.label);
  });
  clusters.forEach((cluster, index) => {
    cluster.colorSeed = index;
  });
  return clusters;
}

// ------------------------------------------------------------------- eras

function eraBuckets(threads) {
  if (!threads.length) return [];
  const dates = threads.map((thread) => thread.updatedAt.getTime());
  const earliest = Math.min(...dates);
  const latest = Math.max(...dates);
  const span = (latest - earliest) / 1000;
  const day = 86_400;

  if (span < day * 130) {
    const byKey = new Map();
    for (const thread of threads) {
      const year = thread.updatedAt.getFullYear();
      const month = thread.updatedAt.getMonth();
      const key = `y${year}-m${String(month + 1).padStart(2, '0')}`;
      if (!byKey.has(key)) byKey.set(key, { date: new Date(year, month, 1), ids: [] });
      byKey.get(key).ids.push(thread.id);
    }
    return [...byKey.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, bucket]) => ({
        key,
        label: bucket.date
          .toLocaleDateString('en-GB', { month: 'short', year: '2-digit' })
          .replace(',', '')
          .toUpperCase(),
        threadIDs: bucket.ids,
      }));
  }

  if (span < day * 365 * 4) {
    const byKey = new Map();
    for (const thread of threads) {
      const year = thread.updatedAt.getFullYear();
      const month = thread.updatedAt.getMonth();
      const quarter = Math.floor(month / 3) + 1;
      const key = `y${year}-q${quarter}`;
      if (!byKey.has(key)) byKey.set(key, { date: new Date(year, (quarter - 1) * 3, 1), quarter, year, ids: [] });
      byKey.get(key).ids.push(thread.id);
    }
    return [...byKey.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, bucket]) => ({
        key,
        label: `Q${bucket.quarter} · ${String(bucket.year % 100).padStart(2, '0')}`,
        threadIDs: bucket.ids,
      }));
  }

  const byYear = new Map();
  for (const thread of threads) {
    const year = String(thread.updatedAt.getFullYear());
    if (!byYear.has(year)) byYear.set(year, []);
    byYear.get(year).push(thread.id);
  }
  return [...byYear.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([year, ids]) => ({ key: `y${year}`, label: year, threadIDs: ids }));
}

// ------------------------------------------------------------------ graph

export function buildGraph(library, filters) {
  const allThreads = library?.threads ?? [];
  const filtered = allThreads.filter((thread) => matchesThread(thread, filters));
  const limited = filtered
    .slice()
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, Math.max(0, filters.maxThreads));

  const baseStats = {
    unfilteredThreadCount: allThreads.length,
  };

  if (!limited.length) {
    return {
      nodes: [makeRootNode(0, 0)],
      edges: [],
      stats: {
        threadCount: 0,
        messageCount: 0,
        tagCount: 0,
        groupCount: 0,
        characterCount: 0,
        earliest: null,
        latest: null,
        totalCost: 0,
        costThreadCount: 0,
        ...baseStats,
      },
      keywordsByThread: new Map(),
      filters,
      isEmpty: true,
    };
  }

  const index = buildIndex(limited, 7);
  const groups = [];
  const groupIDByThread = new Map();

  if (filters.grouping === 'provider') {
    for (const provider of PROVIDERS) {
      const threads = limited.filter((thread) => thread.provider === provider.id);
      if (!threads.length) continue;
      const spec = {
        id: `group:provider:${provider.id}`,
        label: provider.name.toUpperCase(),
        subtitle: threadCountLabel(threads.length),
        provider: provider.id,
        colorSeed: provider.order,
        parentID: null,
        threadIDs: threads.map((thread) => thread.id),
        cost: 0,
      };
      groups.push(spec);
      for (const thread of threads) groupIDByThread.set(thread.id, spec.id);
    }
  } else if (filters.grouping === 'topic') {
    const maxTopics = Math.min(14, Math.max(6, 6 + Math.floor(limited.length / 24)));
    const clusters = buildTopicClusters(limited, index, maxTopics);
    clusters.forEach((cluster, offset) => {
      const spec = {
        id: cluster.id,
        label: cluster.label.toUpperCase(),
        subtitle: threadCountLabel(cluster.threadIDs.length),
        provider: null,
        colorSeed: offset,
        parentID: null,
        threadIDs: cluster.threadIDs,
        cost: 0,
      };
      groups.push(spec);
      for (const threadID of cluster.threadIDs) groupIDByThread.set(threadID, spec.id);
    });
    const leftovers = limited.filter((thread) => !groupIDByThread.has(thread.id));
    if (leftovers.length) {
      const spec = {
        id: 'group:topic:misc',
        label: 'MISCELLANY',
        subtitle: threadCountLabel(leftovers.length),
        provider: null,
        colorSeed: 9,
        parentID: null,
        threadIDs: leftovers.map((thread) => thread.id),
        cost: 0,
      };
      groups.push(spec);
      for (const thread of leftovers) groupIDByThread.set(thread.id, spec.id);
    }
  } else if (filters.grouping === 'era') {
    eraBuckets(limited).forEach((bucket, offset) => {
      const spec = {
        id: `group:era:${bucket.key}`,
        label: bucket.label,
        subtitle: threadCountLabel(bucket.threadIDs.length),
        provider: null,
        colorSeed: offset,
        parentID: null,
        threadIDs: bucket.threadIDs,
        cost: 0,
      };
      groups.push(spec);
      for (const threadID of bucket.threadIDs) groupIDByThread.set(threadID, spec.id);
    });
  }

  const threadByID = new Map(limited.map((thread) => [thread.id, thread]));
  for (const group of groups) {
    group.cost = group.threadIDs.reduce((sum, id) => sum + (threadByID.get(id)?.totalCost ?? 0), 0);
  }

  // Tags ---------------------------------------------------------------
  const minimumTagThreads = limited.length >= 45 ? 3 : 2;
  const tagLimit = limited.length >= 200 ? 90 : limited.length >= 80 ? 60 : 42;
  const tagCounts = Object.create(null);
  const tagScores = Object.create(null);
  const tagsByThread = new Map();

  for (const thread of limited) {
    const keywords = index.keywordsByThread.get(thread.id) ?? [];
    const kept = [];
    for (const keyword of keywords) {
      if ((index.documentFrequency[keyword.term] ?? 0) < minimumTagThreads) continue;
      kept.push(keyword);
      tagCounts[keyword.term] = (tagCounts[keyword.term] ?? 0) + 1;
      tagScores[keyword.term] = (tagScores[keyword.term] ?? 0) + keyword.score;
    }
    tagsByThread.set(thread.id, kept.slice(0, 5));
  }

  const allowedTags = new Set(
    Object.keys(tagCounts)
      .sort((a, b) => {
        const countDiff = (tagCounts[b] ?? 0) - (tagCounts[a] ?? 0);
        if (countDiff !== 0) return countDiff;
        return (tagScores[b] ?? 0) - (tagScores[a] ?? 0);
      })
      .slice(0, tagLimit),
  );

  // Nodes + edges ------------------------------------------------------
  const nodes = [makeRootNode(limited.length, groups.length)];
  const edges = [];
  const tagNodes = new Map();

  groups.forEach((group, groupIndex) => {
    const provider = group.provider ? PROVIDERS.find((item) => item.id === group.provider) : null;
    nodes.push({
      id: group.id,
      kind: 'group',
      label: group.label,
      subtitle: group.subtitle,
      provider: group.provider,
      parentID: group.parentID,
      groupID: null,
      threadID: null,
      tag: null,
      weight: group.threadIDs.length,
      colorSeed: provider ? provider.order : (group.colorSeed + 1) % 12,
      cost: group.cost,
      tokenCount: group.threadIDs.reduce((sum, id) => sum + (threadByID.get(id)?.tokenCount ?? 0), 0),
      threadIDs: group.threadIDs,
    });

    edges.push({
      id: `root->${group.id}`,
      source: 'root',
      target: group.id,
      kind: 'rootGroup',
      weight: Math.max(1, group.threadIDs.length),
    });

    for (const threadID of group.threadIDs) {
      const thread = threadByID.get(threadID);
      if (!thread) continue;
      const nodeID = `thread:${thread.id}`;
      nodes.push({
        id: nodeID,
        kind: 'thread',
        label: thread.title,
        subtitle: thread.model ?? thread.provider,
        provider: thread.provider,
        groupID: group.id,
        threadID: thread.id,
        tag: null,
        parentID: null,
        weight: 1 + Math.min(3, Math.log(1 + thread.messageCount) * 0.55),
        colorSeed: provider ? provider.order : groupIndex % 12,
        cost: thread.totalCost,
        tokenCount: thread.tokenCount,
        messageCount: thread.messageCount,
      });
      edges.push({
        id: `${group.id}->${nodeID}`,
        source: group.id,
        target: nodeID,
        kind: 'groupThread',
        weight: 1 + Math.min(2, thread.messageCount / 40),
      });

      if (!filters.includeTags) continue;
      for (const keyword of tagsByThread.get(thread.id) ?? []) {
        if (!allowedTags.has(keyword.term)) continue;
        const tagID = `tag:${slug(keyword.term)}`;
        if (!tagNodes.has(tagID)) {
          const tagNode = {
            id: tagID,
            kind: 'tag',
            label: keyword.term,
            subtitle: null,
            provider: null,
            groupID: null,
            threadID: null,
            tag: keyword.term,
            parentID: null,
            weight: tagCounts[keyword.term] ?? 1,
            colorSeed: groupIndex % 12,
            cost: 0,
            tokenCount: 0,
          };
          tagNodes.set(tagID, tagNode);
          nodes.push(tagNode);
        }
        edges.push({
          id: `${nodeID}->${tagID}`,
          source: nodeID,
          target: tagID,
          kind: 'threadTag',
          weight: Math.min(1, keyword.score / 12),
        });
      }
    }
  });

  // Drop tag nodes that ended up with no edges.
  if (filters.includeTags) {
    const connected = new Set();
    for (const edge of edges) {
      if (edge.kind !== 'threadTag') continue;
      connected.add(edge.source);
      connected.add(edge.target);
    }
    for (let i = nodes.length - 1; i >= 0; i -= 1) {
      if (nodes[i].kind === 'tag' && !connected.has(nodes[i].id)) nodes.splice(i, 1);
    }
  }

  const messages = limited.reduce((sum, thread) => sum + thread.messageCount, 0);
  const characters = limited.reduce((sum, thread) => sum + thread.characterCount, 0);
  const earliest = limited.reduce((min, thread) => (!min || thread.createdAt < min ? thread.createdAt : min), null);
  const latest = limited.reduce((max, thread) => (!max || thread.updatedAt > max ? thread.updatedAt : max), null);

  return {
    nodes,
    edges,
    stats: {
      threadCount: limited.length,
      messageCount: messages,
      tagCount: nodes.filter((node) => node.kind === 'tag').length,
      groupCount: groups.length,
      characterCount: characters,
      earliest,
      latest,
      unfilteredThreadCount: allThreads.length,
      totalCost: limited.reduce((sum, thread) => sum + thread.totalCost, 0),
      costThreadCount: limited.filter((thread) => thread.hasCostData).length,
    },
    keywordsByThread: tagsByThread,
    filters,
    isEmpty: false,
  };
}

// ---------------------------------------------------------------- helpers

export function nodeColor(node) {
  if (node.kind === 'tag') return topicColor(node.colorSeed);
  if (node.provider) return providerColor(node.provider);
  if (node.kind === 'root') return '#E9F1FF';
  return topicColor(node.colorSeed);
}

/** Port of MindMapGraph.focusPath(for:). */
export function focusPath(graph, nodeID) {
  const node = graph.nodes.find((item) => item.id === nodeID);
  if (!node) return new Set();
  if (node.kind === 'root') return new Set(graph.nodes.map((item) => item.id));

  const result = new Set([node.id]);
  const adjacency = new Map();
  for (const edge of graph.edges) {
    if (!adjacency.has(edge.source)) adjacency.set(edge.source, []);
    if (!adjacency.has(edge.target)) adjacency.set(edge.target, []);
    adjacency.get(edge.source).push(edge.target);
    adjacency.get(edge.target).push(edge.source);
  }
  const byID = new Map(graph.nodes.map((item) => [item.id, item]));

  if (node.kind === 'group') {
    const queue = [node.id];
    const visited = new Set([node.id]);
    while (queue.length) {
      const current = queue.pop();
      for (const other of adjacency.get(current) ?? []) {
        result.add(other);
        const otherNode = byID.get(other);
        if (otherNode?.kind === 'group') {
          if (!visited.has(other)) {
            visited.add(other);
            queue.push(other);
          }
        } else if (otherNode?.kind === 'thread') {
          for (const tag of adjacency.get(other) ?? []) {
            if (byID.get(tag)?.kind === 'tag') result.add(tag);
          }
        }
      }
    }
    let parentID = node.parentID;
    while (parentID && byID.get(parentID)) {
      result.add(parentID);
      parentID = byID.get(parentID).parentID;
    }
    result.add('root');
    return result;
  }

  if (node.kind === 'thread') {
    for (const other of adjacency.get(node.id) ?? []) result.add(other);
    if (node.groupID) result.add(node.groupID);
    result.add('root');
    return result;
  }

  if (node.kind === 'tag') {
    for (const other of adjacency.get(node.id) ?? []) {
      result.add(other);
      const groupID = byID.get(other)?.groupID;
      if (groupID) result.add(groupID);
    }
    result.add('root');
    return result;
  }

  return result;
}

export function resolveTimeWindow(id, now = new Date()) {
  const window = TIME_WINDOWS.find((item) => item.id === id);
  if (!window?.days) return null;
  const since = new Date(now);
  since.setDate(since.getDate() - window.days);
  return since;
}

export function summarizeGraph(graph) {
  const stats = graph.stats;
  const parts = [
    fmtCount(stats.threadCount, 'THREAD', 'THREADS'),
    fmtCount(stats.messageCount, 'MESSAGE', 'MESSAGES'),
    fmtCount(stats.groupCount, 'CONSTELLATION', 'CONSTELLATIONS'),
  ];
  if (stats.tagCount) parts.push(fmtCount(stats.tagCount, 'TAG', 'TAGS'));
  if (stats.costThreadCount) parts.push(`$${stats.totalCost.toFixed(2)}`);
  if (stats.unfilteredThreadCount > stats.threadCount) {
    parts.push(`OF ${stats.unfilteredThreadCount}`);
  }
  return parts.join(' · ');
}

