import Foundation

// MARK: - Shares

/// One row of a thread's region or sub-region profile. Shares are soft and
/// sum to 1, so a conversation can genuinely belong to two domains.
public struct TopicShare: Identifiable, Codable, Hashable, Sendable {
    public var topicID: String
    public var label: String
    public var share: Double
    /// Spend attributed to this region/sub-region for the thread.
    public var cost: Double

    public var id: String { topicID }

    public init(topicID: String, label: String, share: Double, cost: Double = 0) {
        self.topicID = topicID
        self.label = label
        self.share = share
        self.cost = cost
    }

    public var percentage: Int { Int((share * 100).rounded()) }
}

/// A classified stretch of a conversation, ready for the transcript view.
public struct SegmentTopic: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var startMessageIndex: Int
    /// Exclusive upper bound.
    public var endMessageIndex: Int
    public var startedAt: Date?
    public var endedAt: Date?
    public var topicID: String
    public var topicLabel: String
    public var regionID: String
    public var regionLabel: String
    public var confidence: Double
    public var keywords: [String]
    public var characterCount: Int
    public var cost: Double
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int

    public init(
        id: String,
        startMessageIndex: Int,
        endMessageIndex: Int,
        startedAt: Date?,
        endedAt: Date?,
        topicID: String,
        topicLabel: String,
        regionID: String,
        regionLabel: String,
        confidence: Double,
        keywords: [String],
        characterCount: Int,
        cost: Double = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0
    ) {
        self.id = id
        self.startMessageIndex = startMessageIndex
        self.endMessageIndex = endMessageIndex
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.topicID = topicID
        self.topicLabel = topicLabel
        self.regionID = regionID
        self.regionLabel = regionLabel
        self.confidence = confidence
        self.keywords = keywords
        self.characterCount = characterCount
        self.cost = cost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
    }

    public var displayTitle: String { "\(regionLabel) · \(topicLabel)" }
}

// MARK: - Thread profile

public struct ThreadTopicProfile: Codable, Sendable {
    public var threadID: String
    public var contentHash: String
    public var segments: [SegmentTopic]
    public var regions: [TopicShare]
    public var topics: [TopicShare]
    public var primaryRegionID: String
    public var primaryTopicID: String
    public var totalCost: Double
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int
    public var analyzedAt: Date

    public init(
        threadID: String,
        contentHash: String,
        segments: [SegmentTopic],
        regions: [TopicShare],
        topics: [TopicShare],
        primaryRegionID: String,
        primaryTopicID: String,
        totalCost: Double = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        analyzedAt: Date
    ) {
        self.threadID = threadID
        self.contentHash = contentHash
        self.segments = segments
        self.regions = regions
        self.topics = topics
        self.primaryRegionID = primaryRegionID
        self.primaryTopicID = primaryTopicID
        self.totalCost = totalCost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.analyzedAt = analyzedAt
    }
}

// MARK: - Analysis

public struct TopicAnalysis: Codable, Sendable {
    /// Bump when segmentation or scoring behaviour changes; older cached
    /// profiles are then recomputed even if the text is unchanged.
    public var version: Int
    public var taxonomy: TopicTaxonomy
    public var embedderID: String
    public var libraryHash: String
    public var profiles: [String: ThreadTopicProfile]
    public var updatedAt: Date

    public init(
        version: Int = TopicPipeline.pipelineVersion,
        taxonomy: TopicTaxonomy = .default,
        embedderID: String = "hash-256-v1",
        libraryHash: String = "",
        profiles: [String: ThreadTopicProfile] = [:],
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.taxonomy = taxonomy
        self.embedderID = embedderID
        self.libraryHash = libraryHash
        self.profiles = profiles
        self.updatedAt = updatedAt
    }

    public static let empty = TopicAnalysis(profiles: [:], updatedAt: .distantPast)

    public func profile(for threadID: String) -> ThreadTopicProfile? {
        profiles[threadID]
    }

    public var isEmpty: Bool { profiles.isEmpty }
}

// MARK: - Pipeline

/// Segment → classify → smooth → roll up. Pure and deterministic apart from
/// the `analyzedAt` timestamps, so tests and cached runs agree exactly.
public struct TopicPipeline: Sendable {
    public static let pipelineVersion = 2

    public var taxonomy: TopicTaxonomy
    public var embedder: any TopicEmbeddingProvider

    public init(
        taxonomy: TopicTaxonomy = .default,
        embedder: any TopicEmbeddingProvider = HashingEmbedder()
    ) {
        self.taxonomy = taxonomy
        self.embedder = embedder
    }

    public var segmenter: ConversationSegmenter {
        ConversationSegmenter(embedder: embedder)
    }

    // MARK: Single thread

    public func analyze(_ thread: ConversationThread, now: Date = Date()) -> ThreadTopicProfile {
        let index = KeywordExtractor.buildIndex(threads: [thread])
        let classifier = TopicClassifier(taxonomy: taxonomy, embedder: embedder)
        return analyze(
            thread,
            contentHash: Self.contentHash(for: thread),
            classifier: classifier,
            idf: index.idf,
            now: now
        )
    }

    // MARK: Library

    public func analyze(
        _ library: ThreadLibrary,
        cached: TopicAnalysis? = nil,
        now: Date = Date()
    ) -> TopicAnalysis {
        let keywordIndex = KeywordExtractor.buildIndex(threads: library.threads)
        let classifier = TopicClassifier(taxonomy: taxonomy, embedder: embedder)

        let threads = library.threads
        let contentHashes = threads.map { Self.contentHash(for: $0) }
        let hashes = zip(threads, contentHashes).map { "\($0.id):\($1)" }

        let reusable = (cached?.version == Self.pipelineVersion
            && cached?.taxonomy == taxonomy
            && cached?.embedderID == embedder.id) ? cached : nil

        // Classification is CPU-bound. Fan threads across cores; results are
        // written by index so the output stays byte-identical to a serial run.
        var results = [ThreadTopicProfile?](repeating: nil, count: threads.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: threads.count) { index in
            let thread = threads[index]
            let hash = contentHashes[index]
            let profile: ThreadTopicProfile
            if let existing = reusable?.profiles[thread.id],
               existing.contentHash == hash,
               !existing.segments.isEmpty {
                profile = existing
            } else {
                profile = analyze(
                    thread,
                    contentHash: hash,
                    classifier: classifier,
                    idf: keywordIndex.idf,
                    now: now
                )
            }
            lock.lock()
            results[index] = profile
            lock.unlock()
        }

        var profiles: [String: ThreadTopicProfile] = [:]
        profiles.reserveCapacity(threads.count)
        for (index, thread) in threads.enumerated() {
            if let profile = results[index] {
                profiles[thread.id] = profile
            }
        }

        let signature = StableID.hex(hashes.sorted().joined(separator: "|"))
        return TopicAnalysis(
            version: Self.pipelineVersion,
            taxonomy: taxonomy,
            embedderID: embedder.id,
            libraryHash: signature,
            profiles: profiles,
            updatedAt: now
        )
    }

    // MARK: Core

    private func analyze(
        _ thread: ConversationThread,
        contentHash: String,
        classifier: TopicClassifier,
        idf: [String: Double],
        now: Date
    ) -> ThreadTopicProfile {
        let segments = segmenter.segment(thread)
        guard !segments.isEmpty else {
            let fallback = taxonomy.fallbackLeaf
            return ThreadTopicProfile(
                threadID: thread.id,
                contentHash: contentHash,
                segments: [],
                regions: fallback.map { [TopicShare(topicID: $0.parentID ?? $0.id, label: taxonomy.label(for: $0.parentID ?? $0.id), share: 1)] } ?? [],
                topics: fallback.map { [TopicShare(topicID: $0.id, label: $0.label, share: 1)] } ?? [],
                primaryRegionID: fallback?.parentID ?? fallback?.id ?? "emerging",
                primaryTopicID: fallback?.id ?? "emerging/misc",
                totalCost: thread.totalCost,
                inputTokens: thread.inputTokens ?? 0,
                outputTokens: thread.outputTokens ?? 0,
                cachedTokens: thread.cachedTokens ?? 0,
                analyzedAt: now
            )
        }

        // Spend follows the segment. The session total from OpenCode is
        // authoritative, so when long sessions were trimmed on import the
        // visible segment costs are scaled to match it instead of losing the
        // omitted turns entirely.
        var segmentCosts: [Double] = []
        var inputTokens: [Int] = []
        var outputTokens: [Int] = []
        var cachedTokens: [Int] = []
        for segment in segments {
            let lower = max(0, min(thread.messages.count, segment.startMessageIndex))
            let upper = max(lower, min(thread.messages.count, segment.endMessageIndex))
            let slice = thread.messages[lower..<upper]
            segmentCosts.append(slice.reduce(0) { $0 + ($1.cost ?? 0) })
            inputTokens.append(slice.reduce(0) { $0 + ($1.inputTokens ?? 0) })
            outputTokens.append(slice.reduce(0) { $0 + ($1.outputTokens ?? 0) })
            cachedTokens.append(slice.reduce(0) { $0 + ($1.cachedTokens ?? 0) })
        }

        let visibleCost = segmentCosts.reduce(0, +)
        let reportedCost = max(thread.cost ?? 0, visibleCost)
        if reportedCost > visibleCost + 0.0000001 {
            if visibleCost > 0 {
                let factor = reportedCost / visibleCost
                segmentCosts = segmentCosts.map { $0 * factor }
            } else {
                // No per-message cost survived trimming: attribute the
                // session total by the same weight used for region mass.
                let weights = segments.map { segment in
                    max(120, Double(segment.userCharacterCount)
                        + 0.25 * Double(max(0, segment.characterCount - segment.userCharacterCount)))
                }
                let totalWeight = weights.reduce(0, +)
                if totalWeight > 0 {
                    segmentCosts = weights.map { $0 / totalWeight * reportedCost }
                }
            }
        }

        let rawTitlePrior = classifier.distribution(for: thread.title)
        let fallbackID = taxonomy.fallbackLeaf?.id
        // A title like "Project notes" carries no signal; don't let it smear
        // a slice of every segment into Emerging.
        let titlePrior = (rawTitlePrior[fallbackID ?? ""] ?? 0) > 0.6 ? [:] : rawTitlePrior
        let distributions = segments.map { segment in
            classifier.blended(segment.text, with: titlePrior, priorWeight: 0.10)
        }
        let smoothed = Self.viterbi(distributions, taxonomy: taxonomy)

        var leafMass: [String: Double] = [:]
        var leafCost: [String: Double] = [:]
        var segmentRows: [SegmentTopic] = []
        segmentRows.reserveCapacity(segments.count)

        for (index, segment) in segments.enumerated() {
            let distribution = distributions[index]
            // The human's prompt defines the topic; assistant prose is
            // supporting evidence, not a volume contest.
            let assistantCharacters = max(0, segment.characterCount - segment.userCharacterCount)
            let weight = max(120, Double(segment.userCharacterCount) + 0.25 * Double(assistantCharacters))
            for topicID in distribution.keys.sorted() {
                leafMass[topicID, default: 0] += (distribution[topicID] ?? 0) * weight
            }

            let topicID = index < smoothed.count ? smoothed[index] : Self.argmax(distribution)
            let topic = taxonomy.node(id: topicID)
            let regionID = topic?.parentID ?? topicID
            let keywords = KeywordExtractor
                .keywords(inText: segment.text, idf: idf, limit: 4)
                .map(\.term)
            let segmentCost = index < segmentCosts.count ? segmentCosts[index] : 0
            leafCost[topicID, default: 0] += segmentCost
            segmentRows.append(SegmentTopic(
                id: segment.id,
                startMessageIndex: segment.startMessageIndex,
                endMessageIndex: segment.endMessageIndex,
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                topicID: topicID,
                topicLabel: topic?.label ?? "Miscellaneous",
                regionID: regionID,
                regionLabel: taxonomy.label(for: regionID),
                confidence: distribution[topicID] ?? 0,
                keywords: keywords,
                characterCount: segment.characterCount,
                cost: segmentCost,
                inputTokens: index < inputTokens.count ? inputTokens[index] : 0,
                outputTokens: index < outputTokens.count ? outputTokens[index] : 0,
                cachedTokens: index < cachedTokens.count ? cachedTokens[index] : 0
            ))
        }

        let totalMass = leafMass.keys.sorted().reduce(0.0) { $0 + (leafMass[$1] ?? 0) }
        if totalMass > 0 {
            for id in leafMass.keys {
                leafMass[id] = (leafMass[id] ?? 0) / totalMass
            }
        }

        var regionMass: [String: Double] = [:]
        var regionCost: [String: Double] = [:]
        for leafID in leafMass.keys.sorted() {
            let regionID = taxonomy.node(id: leafID)?.parentID ?? leafID
            regionMass[regionID, default: 0] += leafMass[leafID] ?? 0
            regionCost[regionID, default: 0] += leafCost[leafID] ?? 0
        }

        let regions = regionMass
            .map {
                TopicShare(
                    topicID: $0.key,
                    label: taxonomy.label(for: $0.key),
                    share: $0.value,
                    cost: regionCost[$0.key] ?? 0
                )
            }
            .sorted(by: shareOrder)
        let topics = leafMass
            .map {
                TopicShare(
                    topicID: $0.key,
                    label: taxonomy.label(for: $0.key),
                    share: $0.value,
                    cost: leafCost[$0.key] ?? 0
                )
            }
            .sorted(by: shareOrder)

        let totalInput = thread.inputTokens ?? inputTokens.reduce(0, +)
        let totalOutput = thread.outputTokens ?? outputTokens.reduce(0, +)
        let totalCached = thread.cachedTokens ?? cachedTokens.reduce(0, +)

        return ThreadTopicProfile(
            threadID: thread.id,
            contentHash: contentHash,
            segments: segmentRows,
            regions: regions,
            topics: topics,
            primaryRegionID: regions.first?.topicID ?? "emerging",
            primaryTopicID: topics.first?.topicID ?? "emerging/misc",
            totalCost: reportedCost,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cachedTokens: totalCached,
            analyzedAt: now
        )
    }

    // MARK: Smoothing

    /// Viterbi over segment distributions. Staying put is free, moving to a
    /// sibling is cheap, jumping domains is expensive — so a single stray
    /// assistant paragraph does not tear a region apart.
    static func viterbi(_ distributions: [[String: Double]], taxonomy: TopicTaxonomy) -> [String] {
        guard let first = distributions.first, !first.isEmpty else { return [] }
        // Distributions are sparsified independently, so each segment may
        // expose a different leaf set. The state space must be their union.
        var stateSet = Set<String>()
        for distribution in distributions {
            stateSet.formUnion(distribution.keys)
        }
        let states = stateSet.sorted()
        let count = distributions.count
        var scores = [[Double]](repeating: [Double](repeating: -.infinity, count: states.count), count: count)
        var back = [[Int]](repeating: [Int](repeating: 0, count: states.count), count: count)

        for (stateIndex, state) in states.enumerated() {
            scores[0][stateIndex] = log(max(1e-6, first[state] ?? 0))
        }

        for index in 1..<count {
            for (stateIndex, state) in states.enumerated() {
                let emission = log(max(1e-6, distributions[index][state] ?? 0))
                var best = -Double.infinity
                var bestPrevious = 0
                for (previousIndex, previous) in states.enumerated() {
                    let penalty = transitionPenalty(previous, state, taxonomy: taxonomy)
                    let candidate = scores[index - 1][previousIndex] + penalty
                    if candidate > best {
                        best = candidate
                        bestPrevious = previousIndex
                    }
                }
                scores[index][stateIndex] = best + emission
                back[index][stateIndex] = bestPrevious
            }
        }

        guard let finalIndex = scores[count - 1].indices.max(by: { scores[count - 1][$0] < scores[count - 1][$1] }) else {
            return []
        }
        var path = [String](repeating: "", count: count)
        var current = finalIndex
        for index in stride(from: count - 1, through: 0, by: -1) {
            path[index] = states[current]
            if index > 0 { current = back[index][current] }
        }
        return path
    }

    private static func transitionPenalty(_ from: String, _ to: String, taxonomy: TopicTaxonomy) -> Double {
        if from == to { return 0 }
        let fromParent = taxonomy.node(id: from)?.parentID
        let toParent = taxonomy.node(id: to)?.parentID
        if fromParent != nil, fromParent == toParent { return -0.45 }
        return -1.25
    }

    // MARK: Hashing

    public static func contentHash(for thread: ConversationThread) -> String {
        var pieces: [String] = [
            thread.id,
            thread.title,
            "\(thread.messages.count)",
            "\(thread.cost ?? -1)",
            "\(thread.inputTokens ?? -1)",
            "\(thread.outputTokens ?? -1)",
            "\(thread.cachedTokens ?? -1)"
        ]
        pieces.reserveCapacity(thread.messages.count * 7 + 7)
        for message in thread.messages {
            pieces.append(message.id)
            pieces.append(message.role.rawValue)
            pieces.append(message.text)
            pieces.append("\(message.cost ?? -1)")
            pieces.append("\(message.inputTokens ?? -1)")
            pieces.append("\(message.outputTokens ?? -1)")
            pieces.append("\(message.cachedTokens ?? -1)")
        }
        return StableID.hex(pieces.joined(separator: "\u{1f}"))
    }

    public static func libraryHash(for threads: [ConversationThread]) -> String {
        let pieces = threads
            .map { "\($0.id):\(contentHash(for: $0))" }
            .sorted()
        return StableID.hex(pieces.joined(separator: "|"))
    }

    private static func argmax(_ distribution: [String: Double]) -> String {
        distribution.max { a, b in
            if abs(a.value - b.value) > 0.0001 { return a.value < b.value }
            return a.key > b.key
        }?.key ?? "emerging/misc"
    }

    private func shareOrder(_ a: TopicShare, _ b: TopicShare) -> Bool {
        if abs(a.share - b.share) > 0.0001 { return a.share > b.share }
        return a.label < b.label
    }
}
