import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

// This runs in Node.js - don't use client-side code here (browser APIs, JSX...)

const config: Config = {
  title: 'MINDME',
  tagline: 'A local-first constellation of your AI conversations',
  favicon: 'img/favicon.png',

  future: {
    v4: true,
  },

  url: 'https://403access.github.io',
  // GitHub Pages project site. When previewing locally, the site is served
  // from http://localhost:3000/mindme/.
  baseUrl: '/mindme/',
  organizationName: '403access',
  projectName: 'mindme',

  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/403access/mindme/tree/main/website/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/spatial.jpg',
    colorMode: {
      defaultMode: 'dark',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'MINDME',
      logo: {
        alt: 'MINDME app icon',
        src: 'img/logo.png',
        width: 30,
        height: 30,
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docs',
          position: 'left',
          label: 'Docs',
        },
        {
          href: 'https://github.com/403access/mindme',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {label: 'Getting started', to: '/docs/'},
            {label: 'Importing conversations', to: '/docs/importing'},
            {label: 'Visualization', to: '/docs/visualization'},
            {label: 'Development', to: '/docs/development'},
          ],
        },
        {
          title: 'Project',
          items: [
            {label: 'GitHub', href: 'https://github.com/403access/mindme'},
            {
              label: 'Sample exports',
              href: 'https://github.com/403access/mindme/tree/main/MindMap/Samples',
            },
            {label: 'Issues', href: 'https://github.com/403access/mindme/issues'},
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} MINDME. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['swift'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
