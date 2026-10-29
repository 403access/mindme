#!/usr/bin/env node
// Enriches the deterministic Swift demo archive for the spatial build:
// seven conversations become OpenCode sessions with synthetic token counts and
// spend, so the COST overlay is explorable without private data.
//
//   node scripts/prepare-demo.mjs <swift-demo-library.json> [output]
//
// The default output is src/data/demo-library.json.

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const input = process.argv[2] ?? fileURLToPath(new URL('../src/data/demo-library.json', import.meta.url));
const output = process.argv[3] ?? fileURLToPath(new URL('../src/data/demo-library.json', import.meta.url));

const library = JSON.parse(readFileSync(input, 'utf8'));
if (!Array.isArray(library.threads)) {
  console.error('Expected a MINDME library with a threads array.');
  process.exit(1);
}

let enriched = 0;
library.threads.forEach((thread, index) => {
  if (index % 13 !== 0) return;
  enriched += 1;
  const cost = Number((0.42 + (index % 5) * 0.31).toFixed(4));
  const inputTokens = 1800 + (index % 7) * 420;
  const outputTokens = 2600 + (index % 4) * 700;
  const cachedTokens = 900 + (index % 3) * 300;

  thread.provider = 'opencode';
  thread.model = 'deepseek-v4.1-flash';
  thread.cost = cost;
  thread.inputTokens = inputTokens;
  thread.outputTokens = outputTokens;
  thread.cachedTokens = cachedTokens;

  for (let i = thread.messages.length - 1; i >= 0; i -= 1) {
    const message = thread.messages[i];
    if (message.role !== 'assistant') continue;
    message.cost = cost;
    message.inputTokens = inputTokens;
    message.outputTokens = outputTokens;
    message.cachedTokens = cachedTokens;
    break;
  }
});

writeFileSync(output, `${JSON.stringify(library, null, 2)}\n`);
console.log(`Enriched ${enriched} demo threads as OpenCode sessions → ${output}`);
