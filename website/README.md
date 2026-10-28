# MINDME docs

Docusaurus site for [MINDME](https://github.com/403access/mindme).

```bash
npm install
npm start          # http://localhost:3000/mindme/
npm run build      # static output in ./build
npm run serve      # preview the production build
npm run typecheck  # TypeScript checks
```

Content lives in [`docs/`](./docs):

- `intro.md` — landing doc, also served at `/docs/`
- `importing.md` — supported formats, OpenCode, generic schema
- `visualization.md` — graph model, keyword pipeline, layouts, renderer
- `development.md` — build, test, release, architecture, performance

The site is configured for the GitHub Pages project site
`https://403access.github.io/mindme/`, hence `baseUrl: '/mindme/'`. If you deploy to a custom
domain, change `url` and `baseUrl` in `docusaurus.config.ts`.
