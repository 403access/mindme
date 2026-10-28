import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docs: [
    'intro',
    'importing',
    {
      type: 'category',
      label: 'Design',
      collapsed: false,
      items: ['visualization'],
    },
    'development',
  ],
};

export default sidebars;
