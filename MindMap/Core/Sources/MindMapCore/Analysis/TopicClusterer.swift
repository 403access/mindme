import Foundation

public struct TopicCluster: Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var threadIDs: [String]
    public var colorSeed: Int
    public var score: Double

    public init(id: String, label: String, threadIDs: [String], colorSeed: Int, score: Double) {
        self.id = id
        self.label = label
        self.threadIDs = threadIDs
        self.colorSeed = colorSeed
        self.score = score
    }
}

/// Groups conversations into shared "constellations" by their strongest
/// keyword. Deterministic, so re-filtering doesn't shuffle the map.
public enum TopicClusterer {

    public static func clusters(
        threads: [ConversationThread],
        index: KeywordIndex,
        maxTopics: Int = 9,
        minimumSize: Int = 2
    ) -> [TopicCluster] {
        guard threads.count >= 2 else { return [] }

        // Aggregate keyword scores and require the term to appear in at least
        // two conversations.
        var totals: [String: Double] = [:]
        var keywordScoresByThread: [String: [String: Double]] = [:]
        var bestTermByThread: [String: String] = [:]

        for thread in threads {
            let keywords = index.keywords(for: thread.id)
            var termScores: [String: Double] = [:]
            for keyword in keywords {
                termScores[keyword.term] = keyword.score
                totals[keyword.term, default: 0] += keyword.score
            }
            keywordScoresByThread[thread.id] = termScores
            if let best = keywords.first?.term { bestTermByThread[thread.id] = best }
        }

        struct Candidate {
            var term: String
            var total: Double
            var documentFrequency: Int
        }

        let candidates = totals.compactMap { term, total -> Candidate? in
            let df = index.documentFrequency[term] ?? 0
            guard df >= 2 else { return nil }
            return Candidate(term: term, total: total, documentFrequency: df)
        }
        .sorted {
            let l = $0.total * log(Double($0.documentFrequency) + 1.0)
            let r = $1.total * log(Double($1.documentFrequency) + 1.0)
            if abs(l - r) > 0.001 { return l > r }
            return $0.term < $1.term
        }

        var selected: [Candidate] = []
        for candidate in candidates {
            // Avoid near-duplicate topics such as "swift" + "swiftui" when one
            // term contains the other and they cover the same conversations.
            let isDominated = selected.contains { existing in
                (existing.term.contains(candidate.term) || candidate.term.contains(existing.term))
                    && existing.documentFrequency >= candidate.documentFrequency
            }
            if isDominated { continue }
            selected.append(candidate)
            if selected.count >= maxTopics { break }
        }
        guard !selected.isEmpty else { return [] }

        // Assign each thread to its highest scoring selected topic.
        var assignment: [String: String] = [:]
        for thread in threads {
            let termScores = keywordScoresByThread[thread.id] ?? [:]
            let best = selected
                .compactMap { candidate -> (String, Double)? in
                    guard let score = termScores[candidate.term] else { return nil }
                    return (candidate.term, score)
                }
                .max { $0.1 < $1.1 }
            if let best {
                assignment[thread.id] = best.0
            } else if let fallback = bestTermByThread[thread.id],
                      selected.contains(where: { $0.term == fallback }) {
                assignment[thread.id] = fallback
            }
        }

        func build(_ terms: [Candidate]) -> [TopicCluster] {
            var byTerm: [String: [String]] = [:]
            for (threadID, term) in assignment {
                if terms.contains(where: { $0.term == term }) {
                    byTerm[term, default: []].append(threadID)
                }
            }
            return terms.compactMap { candidate in
                guard let ids = byTerm[candidate.term], ids.count >= minimumSize else { return nil }
                return TopicCluster(
                    id: "topic:\(TextTools.slug(candidate.term))",
                    label: candidate.term,
                    threadIDs: ids.sorted(),
                    colorSeed: 0,
                    score: candidate.total
                )
            }
        }

        var working = selected
        var clusters = build(working)

        // Topics that ended up with a single conversation are folded back in:
        // drop them, let those threads fall to their next best surviving topic
        // or to the miscellaneous group.
        for _ in 0..<2 {
            let surviving = Set(clusters.map { $0.label })
            if surviving.count == working.count { break }
            working = working.filter { surviving.contains($0.term) }
            // Reassign threads whose topic was dropped.
            for thread in threads {
                guard let current = assignment[thread.id], !surviving.contains(current) else { continue }
                let termScores = keywordScoresByThread[thread.id] ?? [:]
                let next = working
                    .compactMap { candidate -> (String, Double)? in
                        guard let score = termScores[candidate.term] else { return nil }
                        return (candidate.term, score)
                    }
                    .max { $0.1 < $1.1 }
                if let next {
                    assignment[thread.id] = next.0
                } else {
                    assignment.removeValue(forKey: thread.id)
                }
            }
            clusters = build(working)
        }

        clusters.sort {
            if $0.threadIDs.count != $1.threadIDs.count { return $0.threadIDs.count > $1.threadIDs.count }
            return $0.label < $1.label
        }
        for i in clusters.indices {
            clusters[i].colorSeed = i
        }
        return clusters
    }
}
