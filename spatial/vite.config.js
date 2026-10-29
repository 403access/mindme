import { defineConfig } from 'vite';

// The docs site deploys to https://403access.github.io/mindme/, so the Quest
// build is published at /mindme/quest/. Override with `--base` or MINDME_BASE.
export default defineConfig({
  base: process.env.MINDME_BASE ?? '/',
  server: {
    host: true,
    port: 5173,
  },
  build: {
    target: 'es2022',
    outDir: 'dist',
    emptyOutDir: true,
    sourcemap: false,
    chunkSizeWarningLimit: 1200,
  },
});
