// Normalizes the MINDME library.json (written by the macOS app) and the
// documented generic `{ "threads": [...] }` schema into one in-browser model.

import { parseDate, truncate } from '../util.js';

export function parseProvider(raw) {
  let value = String(raw ?? '').toLowerCase().trim().replaceAll(' ', '');
  if (!value) return 'other';
  if (value.includes('chatgpt') || value.includes('openai') || value === 'gpt') return 'chatgpt';
  if (value.includes('gemini') || value.includes('bard') || value.includes('google')) return 'gemini';
  if (value.includes('claude') || value.includes('anthropic')) return 'claude';
  if (value.includes('opencode')) return 'opencode';
  if (value === 'other') return 'other';
  return 'other';
}

export function parseRole(raw) {
  const value = String(raw ?? '').toLowerCase();
  if (value === 'user' || value === 'human' || value === 'prompt') return 'user';
  if (value === 'assistant' || value === 'ai' || value === 'model' || value === 'bot') return 'assistant';
  if (value === 'system') return 'system';
  if (value === 'tool' || value === 'function') return 'tool';
  return 'assistant';
}

function messageText(raw) {
  if (typeof raw === 'string') return raw;
  if (Array.isArray(raw)) {
    return raw
      .map((part) => {
        if (typeof part === 'string') return part;
        if (part && typeof part === 'object') return part.text ?? part.content ?? '';
        return '';
      })
      .join('\n')
      .trim();
  }
  if (raw && typeof raw === 'object') return raw.text ?? raw.content ?? '';
  return '';
}

function normalizeMessage(raw, index) {
  if (!raw || typeof raw !== 'object') return null;
  const text = String(messageText(raw.text ?? raw.contents ?? raw.content ?? raw.parts) ?? '').trim();
  if (!text) return null;
  const rawCost = raw.cost;
  const cost = rawCost == null || rawCost === '' ? null : Number(rawCost);
  return {
    id: String(raw.id ?? `message-${index}`),
    role: parseRole(raw.role ?? raw.author?.role),
    text,
    timestamp: parseDate(raw.timestamp ?? raw.createdAt ?? raw.create_time ?? raw.created_at),
    cost: Number.isFinite(cost) ? cost : null,
    inputTokens: Number(raw.inputTokens ?? raw.input_tokens) || 0,
    outputTokens: Number(raw.outputTokens ?? raw.output_tokens) || 0,
    cachedTokens: Number(raw.cachedTokens ?? raw.cached_tokens) || 0,
  };
}

function normalizeThread(raw, index) {
  if (!raw || typeof raw !== 'object') return null;
  const rawMessages = Array.isArray(raw.messages) ? raw.messages : [];
  const messages = rawMessages.map(normalizeMessage).filter(Boolean);
  if (!messages.length) return null;

  const createdAt =
    parseDate(raw.createdAt ?? raw.created_at ?? raw.create_time ?? raw.created) ??
    messages.find((message) => message.timestamp)?.timestamp ??
    new Date(0);
  const updatedAt =
    parseDate(raw.updatedAt ?? raw.updated_at ?? raw.update_time) ??
    [...messages].reverse().find((message) => message.timestamp)?.timestamp ??
    createdAt;

  const rawCost = raw.cost;
  const cost = rawCost == null || rawCost === '' ? null : Number(rawCost);
  const totalMessageCost = messages.reduce((sum, message) => sum + (message.cost ?? 0), 0);
  const totalCost = Number.isFinite(cost) ? cost : totalMessageCost;
  const hasCostData = Number.isFinite(cost) || messages.some((message) => message.cost !== null);

  const inputTokens = Number(raw.inputTokens ?? raw.input_tokens) || 0;
  const outputTokens = Number(raw.outputTokens ?? raw.output_tokens) || 0;
  const cachedTokens = Number(raw.cachedTokens ?? raw.cached_tokens) || 0;
  const messageTokens = messages.reduce(
    (sum, message) => sum + message.inputTokens + message.outputTokens + message.cachedTokens,
    0,
  );

  const title = String(raw.title ?? raw.name ?? '').trim() || truncate(
    messages.find((message) => message.role === 'user')?.text ?? messages[0].text,
    70,
  );

  return {
    id: String(raw.id ?? raw.uuid ?? `thread-${index}`),
    provider: parseProvider(raw.provider),
    title,
    createdAt,
    updatedAt,
    messages,
    model: raw.model ? String(raw.model) : null,
    sourceURL: raw.sourceURL ?? raw.source_url ?? raw.url ?? null,
    sourceFile: raw.sourceFile ?? raw.source_file ?? null,
    isDemo: Boolean(raw.isDemo ?? raw.is_demo),
    cost: Number.isFinite(cost) ? cost : null,
    totalCost,
    hasCostData,
    inputTokens,
    outputTokens,
    cachedTokens,
    tokenCount: inputTokens || outputTokens || cachedTokens ? inputTokens + outputTokens + cachedTokens : messageTokens,
    messageCount: messages.length,
    userMessageCount: messages.filter((message) => message.role === 'user').length,
    characterCount: messages.reduce((sum, message) => sum + message.text.length, 0),
    wordCount: messages.reduce((sum, message) => sum + message.text.split(/\s+/).filter(Boolean).length, 0),
  };
}

export class LibraryError extends Error {}

/**
 * Accepts a parsed object or a JSON string. Returns `{ threads, lastImport }`
 * with dates and provider ids normalized, sorted newest first.
 */
export function normalizeLibrary(input) {
  let raw = input;
  if (typeof raw === 'string') {
    try {
      raw = JSON.parse(raw);
    } catch (error) {
      throw new LibraryError(`That file is not valid JSON. ${error.message}`);
    }
  }
  if (Array.isArray(raw)) raw = { threads: raw };
  if (!raw || typeof raw !== 'object') {
    throw new LibraryError('Expected a MINDME library.json or a JSON object with a "threads" array.');
  }
  if (!Array.isArray(raw.threads)) {
    throw new LibraryError('Expected a "threads" array. Export a library from MINDME, or use the documented generic schema.');
  }

  const threads = raw.threads.map(normalizeThread).filter(Boolean);
  if (!threads.length) {
    throw new LibraryError('No readable conversations found. Each thread needs a title and at least one message with text.');
  }
  threads.sort((a, b) => b.updatedAt - a.updatedAt);
  return {
    threads,
    lastImport: parseDate(raw.lastImport),
  };
}

export function libraryStats(library) {
  const threads = library?.threads ?? [];
  const providers = new Set(threads.map((thread) => thread.provider));
  return {
    threads: threads.length,
    messages: threads.reduce((sum, thread) => sum + thread.messageCount, 0),
    characters: threads.reduce((sum, thread) => sum + thread.characterCount, 0),
    providers: providers.size,
    totalCost: threads.reduce((sum, thread) => sum + thread.totalCost, 0),
    costThreads: threads.filter((thread) => thread.hasCostData).length,
    earliest: threads.reduce((min, thread) => (!min || thread.createdAt < min ? thread.createdAt : min), null),
    latest: threads.reduce((max, thread) => (!max || thread.updatedAt > max ? thread.updatedAt : max), null),
  };
}
