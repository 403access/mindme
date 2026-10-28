import Foundation

public struct Keyword: Hashable, Codable, Sendable {
    public var term: String
    public var score: Double

    public init(term: String, score: Double) {
        self.term = term
        self.score = score
    }
}

public struct KeywordIndex: Sendable {
    public var idf: [String: Double]
    public var keywordsByThread: [String: [Keyword]]
    public var documentFrequency: [String: Int]

    public init(
        idf: [String: Double] = [:],
        keywordsByThread: [String: [Keyword]] = [:],
        documentFrequency: [String: Int] = [:]
    ) {
        self.idf = idf
        self.keywordsByThread = keywordsByThread
        self.documentFrequency = documentFrequency
    }

    public func keywords(for threadID: String) -> [Keyword] {
        keywordsByThread[threadID] ?? []
    }
}

/// Lightweight, deterministic keyword extraction. No NLP model, no network:
/// token frequency weighted by role + title, scaled by inverse document
/// frequency across the imported threads.
public enum KeywordExtractor {

    public static let stopwords: Set<String> = [
        // English function words
        "the", "and", "for", "are", "but", "not", "you", "your", "yours", "with", "this", "that",
        "these", "those", "from", "have", "has", "had", "was", "were", "will", "would", "could",
        "should", "can", "may", "might", "must", "shall", "about", "into", "over", "under", "than",
        "then", "there", "their", "them", "they", "what", "when", "where", "which", "while", "who",
        "why", "how", "all", "any", "both", "each", "few", "more", "most", "other", "some", "such",
        "only", "own", "same", "too", "very", "just", "also", "now", "here", "because", "been",
        "being", "does", "did", "doing", "done", "get", "got", "gets", "getting", "make", "made",
        "makes", "making", "use", "used", "uses", "using", "want", "wanted", "need", "needed",
        "like", "liked", "know", "think", "thought", "see", "look", "looks", "one", "two", "three",
        "yes", "okay", "ok", "sure", "well", "really", "much", "many", "lot", "lots", "thing",
        "things", "something", "anything", "nothing", "everything", "someone", "anyone", "everyone",
        "please", "thanks", "thank", "hello", "hey", "hi", "good", "great", "best", "better",
        "possible", "able", "way", "ways", "time", "times", "new", "old", "first", "last", "next",
        "able", "let", "lets", "let's", "im", "ive", "id", "ill", "youre", "you've", "its", "it's",
        "don", "doesn", "didn", "isn", "aren", "wasn", "weren", "won", "wouldn", "couldn", "shouldn",
        "can", "cannot", "won't", "don't", "doesn't", "isn't", "aren't", "wasn't", "weren't",
        "http", "https", "www", "com", "org", "net", "html", "json", "true", "false", "null",
        "etc", "eg", "ie", "per", "via", "vs", "within", "without", "across", "between", "during",
        "before", "after", "above", "below", "again", "further", "once", "off", "out", "up", "down",
        "on", "in", "at", "by", "to", "of", "or", "as", "an", "is", "it", "be", "do", "if", "so",
        "no", "we", "he", "she", "his", "her", "him", "our", "us", "my", "me", "i", "a",
        // German function words (the app is used in mixed-language chats)
        "und", "oder", "aber", "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen",
        "einem", "einer", "ist", "sind", "war", "waren", "ich", "du", "er", "sie", "es", "wir",
        "ihr", "mich", "mir", "dich", "dir", "uns", "euch", "nicht", "kein", "keine", "mit", "für",
        "auf", "aus", "bei", "nach", "über", "unter", "vor", "durch", "von", "zum", "zur", "um",
        "im", "am", "an", "in", "als", "wie", "was", "wer", "wo", "wann", "warum", "wie", "dass",
        "wenn", "dann", "noch", "nur", "auch", "schon", "sehr", "mehr", "viel", "viele", "mal",
        "so", "man", "sich", "haben", "hat", "hatte", "werden", "wird", "wurde", "kann", "können",
        "muss", "müssen", "soll", "sollen", "bitte", "danke", "hallo", "ja", "nein", "doch",
        "gerne", "gut", "besser", "jetzt", "hier", "da", "dort", "immer", "wieder", "etwas",
        "nichts", "alles", "mein", "meine", "dein", "deine", "unser", "unsere", "dieser", "diese",
        "dieses", "welche", "welcher", "welches", "einem", "eines", "bin", "bist", "seid",
        // chat / assistant boilerplate
        "assistant", "user", "system", "message", "answer", "question", "response", "prompt",
        "help", "helps", "helpful", "explain", "explanation", "example", "examples", "sure",
        "below", "following", "consider", "note", "important", "option", "options", "step", "steps",
        "summary", "summary", "answer", "based", "provide", "provide", "include", "including",
        "recommend", "recommendation", "suggest", "suggestion", "ensure", "process", "create",
        "build", "building", "start", "starting", "write", "writing", "written", "add", "added"
    ]

    // Very generic AI-domain words that produce useless clusters on their own.
    private static let weakTerms: Set<String> = [
        "model", "models", "data", "tool", "tools", "code", "project", "app", "application",
        "content", "idea", "ideas", "problem", "solution", "feature", "features", "work", "working",
        "test", "testing", "error", "issue", "case", "value", "type", "file", "files", "list",
        "number", "name", "point", "part", "place", "world", "people", "person", "day", "days",
        "year", "years", "month", "week", "today", "tomorrow", "yesterday", "morning", "evening",
        "thing", "stuff", "kind", "sort", "level", "result", "results", "simple", "quick",
        "using", "based", "able", "possible", "likely", "different", "similar", "various",
        "specific", "general", "main", "small", "large", "big", "high", "low", "long", "short",
        "right", "left", "top", "bottom", "front", "back", "end", "start", "begin", "change",
        "changes", "update", "updates", "version", "default", "current", "existing", "actual"
    ]

    public static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        tokens.reserveCapacity(text.count / 6)
        for raw in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            var token = String(raw)
            guard token.count >= 3, token.count <= 32 else { continue }
            guard token.contains(where: \.isLetter) else { continue }
            guard !stopwords.contains(token), !weakTerms.contains(token) else { continue }
            guard !token.allSatisfy(\.isNumber) else { continue }
            // Very light singularization, enough to merge "agents"/"agent".
            if token.count > 4, token.hasSuffix("s"),
               !token.hasSuffix("ss"), !token.hasSuffix("us"), !token.hasSuffix("is"),
               !token.hasSuffix("as"), !token.hasSuffix("os"), !token.hasSuffix("ics"),
               !token.hasSuffix("ous") {
                token.removeLast()
            }
            tokens.append(token)
        }
        return tokens
    }

    public static func buildIndex(threads: [ConversationThread], limitPerThread: Int = 6) -> KeywordIndex {
        guard !threads.isEmpty else { return KeywordIndex() }

        var documentFrequency: [String: Int] = [:]
        var tokenSets: [String: Set<String>] = [:]
        for thread in threads {
            var seen = Set<String>()
            for message in thread.messages where message.role != .system && message.role != .tool {
                for token in tokenize(message.text) {
                    seen.insert(token)
                }
            }
            for token in tokenize(thread.title) { seen.insert(token) }
            tokenSets[thread.id] = seen
            for token in seen {
                documentFrequency[token, default: 0] += 1
            }
        }

        let total = Double(threads.count)
        var idf: [String: Double] = [:]
        idf.reserveCapacity(documentFrequency.count)
        for (term, df) in documentFrequency {
            idf[term] = log((total + 1.0) / (Double(df) + 0.5)) + 1.0
        }

        var keywordsByThread: [String: [Keyword]] = [:]
        for thread in threads {
            keywordsByThread[thread.id] = keywords(
                for: thread,
                idf: idf,
                limit: limitPerThread
            )
        }

        return KeywordIndex(
            idf: idf,
            keywordsByThread: keywordsByThread,
            documentFrequency: documentFrequency
        )
    }

    public static func keywords(for thread: ConversationThread, idf: [String: Double], limit: Int = 6) -> [Keyword] {
        var scores: [String: Double] = [:]

        func add(_ text: String, weight: Double) {
            var counts: [String: Int] = [:]
            for token in tokenize(text) {
                counts[token, default: 0] += 1
            }
            for (token, count) in counts {
                // Diminishing returns for repeated words inside one message.
                let frequency = 1.0 + log(Double(min(count, 8)))
                scores[token, default: 0] += frequency * weight
            }
        }

        add(thread.title, weight: 3.4)
        for message in thread.messages {
            switch message.role {
            case .user:
                add(TextTools.truncated(message.text, limit: 1600), weight: 1.8)
            case .assistant:
                add(TextTools.truncated(message.text, limit: 2600), weight: 0.9)
            case .system, .tool:
                continue
            }
        }

        let ranked = scores.map { term, raw -> Keyword in
            let boost = idf[term] ?? 1.0
            // Title terms are the strongest signal for a conversation's topic.
            let titleBoost = tokenize(thread.title).contains(term) ? 1.55 : 1.0
            return Keyword(term: term, score: raw * boost * titleBoost)
        }
        .sorted {
            if abs($0.score - $1.score) > 0.0001 { return $0.score > $1.score }
            return $0.term < $1.term
        }

        return Array(ranked.prefix(limit))
    }

    public static func prettyLabel(_ term: String) -> String {
        guard let first = term.first else { return term }
        return first.uppercased() + term.dropFirst()
    }
}
