// Port of MindMap/Core/Sources/MindMapCore/Analysis/KeywordExtractor.swift.
// Deterministic TF-IDF-ish keyword extraction: same stopwords, tokenization,
// title boost, and singularization as the macOS app, so tag nodes agree.

const STOPWORDS = new Set([
  // English function words
  'the', 'and', 'for', 'are', 'but', 'not', 'you', 'your', 'yours', 'with', 'this', 'that',
  'these', 'those', 'from', 'have', 'has', 'had', 'was', 'were', 'will', 'would', 'could',
  'should', 'can', 'may', 'might', 'must', 'shall', 'about', 'into', 'over', 'under', 'than',
  'then', 'there', 'their', 'them', 'they', 'what', 'when', 'where', 'which', 'while', 'who',
  'why', 'how', 'all', 'any', 'both', 'each', 'few', 'more', 'most', 'other', 'some', 'such',
  'only', 'own', 'same', 'too', 'very', 'just', 'also', 'now', 'here', 'because', 'been',
  'being', 'does', 'did', 'doing', 'done', 'get', 'got', 'gets', 'getting', 'make', 'made',
  'makes', 'making', 'use', 'used', 'uses', 'using', 'want', 'wanted', 'need', 'needed',
  'like', 'liked', 'know', 'think', 'thought', 'see', 'look', 'looks', 'one', 'two', 'three',
  'yes', 'okay', 'ok', 'sure', 'well', 'really', 'much', 'many', 'lot', 'lots', 'thing',
  'things', 'something', 'anything', 'nothing', 'everything', 'someone', 'anyone', 'everyone',
  'please', 'thanks', 'thank', 'hello', 'hey', 'hi', 'good', 'great', 'best', 'better',
  'possible', 'able', 'way', 'ways', 'time', 'times', 'new', 'old', 'first', 'last', 'next',
  'able', 'let', 'lets', "let's", 'im', 'ive', 'id', 'ill', 'youre', "you've", 'its', "it's",
  'don', 'doesn', 'didn', 'isn', 'aren', 'wasn', 'weren', 'won', 'wouldn', 'couldn', 'shouldn',
  'can', 'cannot', "won't", "don't", "doesn't", "isn't", "aren't", "wasn't", "weren't",
  'http', 'https', 'www', 'com', 'org', 'net', 'html', 'json', 'true', 'false', 'null',
  'etc', 'eg', 'ie', 'per', 'via', 'vs', 'within', 'without', 'across', 'between', 'during',
  'before', 'after', 'above', 'below', 'again', 'further', 'once', 'off', 'out', 'up', 'down',
  'on', 'in', 'at', 'by', 'to', 'of', 'or', 'as', 'an', 'is', 'it', 'be', 'do', 'if', 'so',
  'no', 'we', 'he', 'she', 'his', 'her', 'him', 'our', 'us', 'my', 'me', 'i', 'a',
  // German function words
  'und', 'oder', 'aber', 'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen',
  'einem', 'einer', 'ist', 'sind', 'war', 'waren', 'ich', 'du', 'er', 'sie', 'es', 'wir',
  'ihr', 'mich', 'mir', 'dich', 'dir', 'uns', 'euch', 'nicht', 'kein', 'keine', 'mit', 'für',
  'auf', 'aus', 'bei', 'nach', 'über', 'unter', 'vor', 'durch', 'von', 'zum', 'zur', 'um',
  'im', 'am', 'an', 'als', 'wie', 'was', 'wer', 'wo', 'wann', 'warum', 'dass',
  'wenn', 'dann', 'noch', 'nur', 'auch', 'schon', 'sehr', 'mehr', 'viel', 'viele', 'mal',
  'so', 'man', 'sich', 'haben', 'hat', 'hatte', 'werden', 'wird', 'wurde', 'kann', 'können',
  'muss', 'müssen', 'soll', 'sollen', 'bitte', 'danke', 'hallo', 'ja', 'nein', 'doch',
  'gerne', 'gut', 'besser', 'jetzt', 'hier', 'da', 'dort', 'immer', 'wieder', 'etwas',
  'nichts', 'alles', 'mein', 'meine', 'dein', 'deine', 'unser', 'unsere', 'dieser', 'diese',
  'dieses', 'welche', 'welcher', 'welches', 'eines', 'bin', 'bist', 'seid',
  // Chat / assistant boilerplate
  'assistant', 'user', 'system', 'message', 'answer', 'question', 'response', 'prompt',
  'help', 'helps', 'helpful', 'explain', 'explanation', 'example', 'examples',
  'below', 'following', 'consider', 'note', 'important', 'option', 'options', 'step', 'steps',
  'summary', 'based', 'provide', 'include', 'including',
  'recommend', 'recommendation', 'suggest', 'suggestion', 'ensure', 'process', 'create',
  'build', 'building', 'start', 'starting', 'write', 'writing', 'written', 'add', 'added',
]);

const WEAK_TERMS = new Set([
  'model', 'models', 'data', 'tool', 'tools', 'code', 'project', 'app', 'application',
  'content', 'idea', 'ideas', 'problem', 'solution', 'feature', 'features', 'work', 'working',
  'test', 'testing', 'error', 'issue', 'case', 'value', 'type', 'file', 'files', 'list',
  'number', 'name', 'point', 'part', 'place', 'world', 'people', 'person', 'day', 'days',
  'year', 'years', 'month', 'week', 'today', 'tomorrow', 'yesterday', 'morning', 'evening',
  'thing', 'stuff', 'kind', 'sort', 'level', 'result', 'results', 'simple', 'quick',
  'using', 'based', 'able', 'possible', 'likely', 'different', 'similar', 'various',
  'specific', 'general', 'main', 'small', 'large', 'big', 'high', 'low', 'long', 'short',
  'right', 'left', 'top', 'bottom', 'front', 'back', 'end', 'start', 'begin', 'change',
  'changes', 'update', 'updates', 'version', 'default', 'current', 'existing', 'actual',
]);

const LETTER = /\p{L}/u;
const SPLIT = /[^\p{L}\p{N}]+/u;

export function tokenize(text) {
  const tokens = [];
  for (const raw of String(text ?? '').toLowerCase().split(SPLIT)) {
    let token = raw;
    if (token.length < 3 || token.length > 32) continue;
    if (!LETTER.test(token)) continue;
    if (STOPWORDS.has(token) || WEAK_TERMS.has(token)) continue;
    if (/^\p{N}+$/u.test(token)) continue;
    if (token.length > 4 && token.endsWith('ies')) {
      token = `${token.slice(0, -3)}y`;
    } else if (
      token.length > 4 &&
      (token.endsWith('oes') || token.endsWith('ches') || token.endsWith('shes') || token.endsWith('xes'))
    ) {
      token = token.slice(0, -2);
    } else if (
      token.length > 4 &&
      token.endsWith('s') &&
      !token.endsWith('ss') &&
      !token.endsWith('us') &&
      !token.endsWith('is') &&
      !token.endsWith('as') &&
      !token.endsWith('os') &&
      !token.endsWith('ics') &&
      !token.endsWith('ous')
    ) {
      token = token.slice(0, -1);
    }
    tokens.push(token);
  }
  return tokens;
}

export function buildIndex(threads, limitPerThread = 7) {
  if (!threads.length) {
    return { idf: {}, keywordsByThread: {}, documentFrequency: {} };
  }
  const documentFrequency = Object.create(null);
  const tokenSets = new Map();

  for (const thread of threads) {
    const seen = new Set();
    for (const message of thread.messages) {
      if (message.role === 'system' || message.role === 'tool') continue;
      for (const token of tokenize(message.text)) seen.add(token);
    }
    for (const token of tokenize(thread.title)) seen.add(token);
    tokenSets.set(thread.id, seen);
    for (const token of seen) documentFrequency[token] = (documentFrequency[token] ?? 0) + 1;
  }

  const total = threads.length;
  const idf = Object.create(null);
  for (const [term, df] of Object.entries(documentFrequency)) {
    idf[term] = Math.log((total + 1) / (df + 0.5)) + 1;
  }

  const keywordsByThread = new Map();
  for (const thread of threads) {
    keywordsByThread.set(thread.id, keywordsForThread(thread, idf, limitPerThread));
  }

  return { idf, keywordsByThread, documentFrequency };
}

export function keywordsForThread(thread, idf, limit = 6) {
  const scores = Object.create(null);
  const add = (text, weight) => {
    const counts = Object.create(null);
    for (const token of tokenize(text)) counts[token] = (counts[token] ?? 0) + 1;
    for (const [token, count] of Object.entries(counts)) {
      const frequency = 1 + Math.log(Math.min(count, 8));
      scores[token] = (scores[token] ?? 0) + frequency * weight;
    }
  };

  add(thread.title, 3.4);
  for (const message of thread.messages) {
    if (message.role === 'user') add(message.text.slice(0, 1600), 1.8);
    else if (message.role === 'assistant') add(message.text.slice(0, 2600), 0.9);
  }

  const titleTokens = new Set(tokenize(thread.title));
  const ranked = Object.entries(scores)
    .map(([term, raw]) => ({
      term,
      score: raw * (idf[term] ?? 1) * (titleTokens.has(term) ? 1.55 : 1),
    }))
    .sort((a, b) => (Math.abs(a.score - b.score) > 0.0001 ? b.score - a.score : a.term.localeCompare(b.term)));

  return ranked.slice(0, limit);
}

export function prettyLabel(term) {
  if (!term) return term;
  return term[0].toUpperCase() + term.slice(1);
}
