import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';

import styles from './index.module.css';

const features = [
  {
    title: 'A map, not a search box',
    body: 'Conversations become nodes, providers become hubs, and shared keywords become diamond tags that bridge clusters without merging them.',
  },
  {
    title: 'Local-first by default',
    body: 'ChatGPT, Gemini, Claude, and OpenCode exports are parsed on your Mac. No accounts, no network calls, no telemetry.',
  },
  {
    title: 'Flat or spatial',
    body: 'Read the map as a force-directed constellation, then flip into an orbit-camera 3D view that preserves every node and edge.',
  },
];

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={styles.hero}>
      <div className="container">
        <div className={styles.heroInner}>
          <span className={styles.eyebrow}>MACOS · LOCAL-FIRST · OPEN SOURCE</span>
          <Heading as="h1" className={styles.title}>
            {siteConfig.title}
          </Heading>
          <p className={styles.tagline}>{siteConfig.tagline}</p>
          <div className={styles.buttons}>
            <Link className="button button--primary button--lg" to="/docs/">
              Read the docs
            </Link>
            <Link
              className="button button--outline button--secondary button--lg"
              href="https://github.com/403access/mindme">
              View on GitHub
            </Link>
          </div>
        </div>
        <div className={styles.screenshotFrame}>
          <img
            className={styles.screenshot}
            src={useBaseUrl('/img/map.jpg')}
            alt="MINDME constellation map showing provider hubs, conversation nodes, and shared keyword tags"
          />
        </div>
      </div>
    </header>
  );
}

export default function Home(): ReactNode {
  return (
    <Layout
      title="A local-first constellation of your AI conversations"
      description="MINDME turns ChatGPT, Gemini, Claude, and OpenCode exports into an explorable constellation of sources, topics, and shared language.">
      <HomepageHeader />
      <main className="container">
        <section className={styles.features}>
          {features.map((feature) => (
            <article key={feature.title} className={styles.feature}>
              <h3>{feature.title}</h3>
              <p>{feature.body}</p>
            </article>
          ))}
        </section>
        <section className={styles.deepDive}>
          <div>
            <h2>How the visualization works</h2>
            <p>
              Keywords never drive type size here. They become topology — diamonds and
              hubs — while conversations keep their identity. The visualization guide walks
              through the graph builder, TF-IDF extraction, both layouts, the cameras, and
              every renderer pass.
            </p>
          </div>
          <Link className={clsx('button button--primary')} to="/docs/visualization">
            Visualization deep dive →
          </Link>
        </section>
      </main>
    </Layout>
  );
}
