// Small shared helpers: formatting, stable hashing, and canvas text layout.

export const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

export function fmtCount(value, singular, plural) {
  const n = Number(value) || 0;
  return `${n.toLocaleString('en-US')} ${n === 1 ? singular : plural}`;
}

export function fmtCompact(value) {
  const n = Number(value) || 0;
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(n >= 10_000_000 ? 0 : 1)}m`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(n >= 10_000 ? 0 : 1)}k`;
  return String(n);
}

export function fmtDate(value) {
  if (!value) return '—';
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }).toUpperCase();
}

export function fmtDateTime(value) {
  if (!value) return '';
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleString('en-GB', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).toUpperCase();
}

export function fmtMoney(value) {
  const n = Number(value) || 0;
  if (n <= 0) return '$0.00';
  if (n < 0.01) return `$${n.toFixed(4)}`;
  if (n < 100) return `$${n.toFixed(2)}`;
  return `$${Math.round(n).toLocaleString('en-US')}`;
}

/** FNV-1a 32 bit — deterministic across launches, used for layout jitter. */
export function hash32(text) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

export function slug(text) {
  const raw = String(text ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return raw.split('-').filter(Boolean).slice(0, 6).join('-');
}

export function truncate(text, limit = 160) {
  const value = String(text ?? '').replace(/\s+/g, ' ').trim();
  if (value.length <= limit) return value;
  const cut = value.slice(0, limit);
  const space = cut.lastIndexOf(' ');
  return `${cut.slice(0, space > limit * 0.6 ? space : limit).trimEnd()}…`;
}

export function escapeHtml(text) {
  return String(text ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export function parseDate(value) {
  if (!value) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value === 'number') {
    // Swift's ISO8601 encoder emits strings; tolerate Unix seconds or millis.
    const ms = value < 10_000_000_000 ? value * 1000 : value;
    const date = new Date(ms);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

// ------------------------------------------------------------------ canvas

export const FONT_MONO = 'ui-monospace, "SF Mono", "JetBrains Mono", "Roboto Mono", Menlo, monospace';
export const FONT_SANS = '-apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, sans-serif';

export function roundedRect(ctx, x, y, w, h, radius) {
  const r = Math.min(radius, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/** Greedy word wrap that also breaks very long tokens. */
export function wrapLines(ctx, text, maxWidth) {
  const paragraphs = String(text ?? '').replace(/\r/g, '').split('\n');
  const lines = [];
  for (const paragraph of paragraphs) {
    if (!paragraph.trim()) {
      lines.push('');
      continue;
    }
    const words = paragraph.split(/(\s+)/);
    let line = '';
    const push = () => {
      if (line.trim()) lines.push(line.trimEnd());
      line = '';
    };
    for (const word of words) {
      if (!word) continue;
      const candidate = line + word;
      if (line && ctx.measureText(candidate).width > maxWidth) {
        push();
        if (word.trim()) line = word.trimStart();
      } else if (!line && ctx.measureText(word).width > maxWidth) {
        // Break a long unbroken token character by character.
        let chunk = '';
        for (const char of word) {
          if (ctx.measureText(chunk + char).width > maxWidth && chunk) {
            lines.push(chunk);
            chunk = char;
          } else {
            chunk += char;
          }
        }
        line = chunk;
      } else {
        line = candidate;
      }
    }
    push();
  }
  return lines;
}

export function hexToRgb(hex) {
  const value = hex.replace('#', '');
  const full = value.length === 3 ? value.split('').map((c) => c + c).join('') : value;
  const int = Number.parseInt(full, 16);
  return { r: (int >> 16) & 255, g: (int >> 8) & 255, b: int & 255 };
}

export function withAlpha(hex, alpha) {
  const { r, g, b } = hexToRgb(hex);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

export function shade(hex, factor) {
  const { r, g, b } = hexToRgb(hex);
  const mix = (channel) => clamp(Math.round(channel * factor), 0, 255);
  return `rgb(${mix(r)}, ${mix(g)}, ${mix(b)})`;
}

export function debounce(fn, delay) {
  let timer = null;
  return (...args) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
}

/** Tiny event emitter used by the app controller. */
export class Emitter {
  constructor() {
    this.listeners = new Map();
  }

  on(event, handler) {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set());
    this.listeners.get(event).add(handler);
    return () => this.off(event, handler);
  }

  off(event, handler) {
    this.listeners.get(event)?.delete(handler);
  }

  emit(event, payload) {
    for (const handler of this.listeners.get(event) ?? []) {
      try {
        handler(payload);
      } catch (error) {
        console.error(`[mindme] listener for "${event}" failed`, error);
      }
    }
  }
}
