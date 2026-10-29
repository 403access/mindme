// MINDME HUD palette, mirroring MindMap/App/Theme.swift.

export const HUD = {
  void: '#04060B',
  deep: '#070B14',
  panel: '#0A111C',
  panelRaised: '#0D1522',
  accent: '#5FE3FF',
  magenta: '#FF5FD2',
  lime: '#B6FF6B',
  amber: '#FFC46B',
  text: '#E9F1FF',
  textSoft: '#A9B6CC',
  muted: '#71809A',
  dim: '#3D485C',
  hairline: 'rgba(255,255,255,0.08)',
};

export const TOPIC_PALETTE = [
  '#5FE3FF',
  '#FF6BCB',
  '#B8FF6B',
  '#FFC46B',
  '#9D8CFF',
  '#5CFFD8',
  '#FF8FA3',
  '#6BA8FF',
  '#E8D66B',
  '#D59CFF',
  '#7CFFB2',
  '#FFA45C',
];

export const PROVIDERS = [
  { id: 'chatgpt', name: 'ChatGPT', short: 'GPT', color: '#4FF0B4', order: 0 },
  { id: 'gemini', name: 'Gemini', short: 'GEM', color: '#7C9CFF', order: 1 },
  { id: 'claude', name: 'Claude', short: 'CLD', color: '#FF9A6B', order: 2 },
  { id: 'opencode', name: 'OpenCode', short: 'OPC', color: '#FFD166', order: 3 },
  { id: 'other', name: 'Other', short: 'OTH', color: '#C9B6FF', order: 4 },
];

export const PROVIDER_BY_ID = Object.fromEntries(PROVIDERS.map((p) => [p.id, p]));

export function providerMeta(id) {
  return PROVIDER_BY_ID[id] ?? PROVIDER_BY_ID.other;
}

export function providerColor(id) {
  return providerMeta(id).color;
}

export function topicColor(seed) {
  const index = ((seed % TOPIC_PALETTE.length) + TOPIC_PALETTE.length) % TOPIC_PALETTE.length;
  return TOPIC_PALETTE[index];
}

/** Mint → amber → coral, matching HUD.spendColor. */
export function spendColor(intensity) {
  const t = Math.max(0, Math.min(1, intensity));
  const stops = [
    [0, [0x4f, 0xf0, 0xb4]],
    [0.55, [0xff, 0xc4, 0x6b]],
    [1, [0xff, 0x6b, 0x7d]],
  ];
  for (let i = 1; i < stops.length; i += 1) {
    const [at, to] = stops[i];
    const [prevAt, from] = stops[i - 1];
    if (t <= at) {
      const k = (t - prevAt) / (at - prevAt);
      const mix = from.map((c, channel) => Math.round(c + (to[channel] - c) * k));
      return `rgb(${mix[0]}, ${mix[1]}, ${mix[2]})`;
    }
  }
  return '#FF6B7D';
}

export const MONO = 'ui-monospace, "SF Mono", "JetBrains Mono", "Roboto Mono", Menlo, monospace';
export const SANS = '-apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, sans-serif';
