import Foundation

/// A contiguous stretch of a conversation that talks about one thing.
public struct ConversationSegment: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var threadID: String
    /// Index of the first message in `ConversationThread.messages`.
    public var startMessageIndex: Int
    /// Exclusive upper bound.
    public var endMessageIndex: Int
    public var startedAt: Date?
    public var endedAt: Date?
    public var text: String
    public var characterCount: Int
    /// Characters the human wrote. User intent weighs more than a verbose
    /// assistant answer when a thread is rolled up into regions.
    public var userCharacterCount: Int
    public var turnCount: Int

    public init(
        id: String,
        threadID: String,
        startMessageIndex: Int,
        endMessageIndex: Int,
        startedAt: Date?,
        endedAt: Date?,
        text: String,
        characterCount: Int,
        userCharacterCount: Int,
        turnCount: Int
    ) {
        self.id = id
        self.threadID = threadID
        self.startMessageIndex = startMessageIndex
        self.endMessageIndex = endMessageIndex
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.text = text
        self.characterCount = characterCount
        self.userCharacterCount = userCharacterCount
        self.turnCount = turnCount
    }
}

/// Splits a thread where the topic actually changes: a vocabulary shift, a
/// time gap, or an explicit cue ("let's switch to the contract"). Exchange
/// boundaries keep user intent and the assistant answer together.
public struct ConversationSegmenter: Sendable {
    public var minimumSegmentTurns: Int
    public var maximumSegments: Int
    public var maximumAssistantCharacters: Int
    private let embedder: any TopicEmbeddingProvider

    public init(
        embedder: any TopicEmbeddingProvider = HashingEmbedder(),
        minimumSegmentTurns: Int = 2,
        maximumSegments: Int = 16,
        maximumAssistantCharacters: Int = 1_600
    ) {
        self.embedder = embedder
        self.minimumSegmentTurns = minimumSegmentTurns
        self.maximumSegments = maximumSegments
        self.maximumAssistantCharacters = maximumAssistantCharacters
    }

    // MARK: - Unit extraction

    struct Unit {
        var start: Int
        var end: Int
        var text: String
        var userText: String
        var startedAt: Date?
        var endedAt: Date?
        var characterCount: Int
        var userCharacterCount: Int
        var tokens: Set<String>
    }

    func units(for thread: ConversationThread) -> [Unit] {
        var units: [Unit] = []

        for (index, message) in thread.messages.enumerated() {
            guard message.role != .system, message.role != .tool else { continue }
            let text = message.role == .assistant
                ? TextTools.truncated(message.text, limit: maximumAssistantCharacters)
                : TextTools.truncated(message.text, limit: 4_000)
            guard !text.isEmpty else { continue }

            let startsExchange = message.role == .user || units.isEmpty
            if startsExchange {
                units.append(Unit(
                    start: index,
                    end: index + 1,
                    text: text,
                    userText: message.role == .user ? text : "",
                    startedAt: message.timestamp,
                    endedAt: message.timestamp,
                    characterCount: text.count,
                    userCharacterCount: message.role == .user ? text.count : 0,
                    tokens: Set(KeywordExtractor.tokenize(text))
                ))
            } else {
                var unit = units.removeLast()
                unit.end = index + 1
                unit.text += "\n" + text
                unit.characterCount += text.count
                if message.role == .user { unit.userCharacterCount += text.count }
                if let timestamp = message.timestamp {
                    unit.endedAt = timestamp
                    if unit.startedAt == nil { unit.startedAt = timestamp }
                }
                unit.tokens.formUnion(KeywordExtractor.tokenize(text))
                units.append(unit)
            }
        }

        return units
    }

    // MARK: - Segmentation

    public func segment(_ thread: ConversationThread) -> [ConversationSegment] {
        let units = units(for: thread)
        guard !units.isEmpty else { return [] }
        guard units.count > 1 else {
            return [makeSegment(thread: thread, units: units, range: 0..<units.count, ordinal: 0)]
        }

        let embeddings = units.map { embedder.embed($0.text) }
        var boundaryScores = [Double](repeating: 0, count: units.count)
        for index in 1..<units.count {
            let similarity = TopicVector.dot(embeddings[index - 1], embeddings[index])
            let vocabularyShift = 1.0 - jaccard(units[index - 1].tokens, units[index].tokens)
            let gap = timeGap(previous: units[index - 1].endedAt, next: units[index].startedAt)
            let cue = cueStrength(units[index].userText)
            boundaryScores[index] = 0.55 * (1.0 - similarity)
                + 0.20 * vocabularyShift
                + 0.10 * gap
                + 0.15 * cue
        }

        let internalScores = Array(boundaryScores.dropFirst())
        let mean = internalScores.reduce(0, +) / Double(internalScores.count)
        let variance = internalScores.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(internalScores.count)
        let deviation = variance.squareRoot()
        let minimumTurns = units.count >= 6 ? max(1, minimumSegmentTurns) : 1
        let threshold = min(0.62, max(0.28, mean + 0.50 * deviation))

        var cuts = [0]
        var segmentStart = 0
        for index in 1..<units.count {
            let remaining = units.count - index
            guard boundaryScores[index] >= threshold,
                  index - segmentStart >= minimumTurns,
                  remaining >= minimumTurns else { continue }
            cuts.append(index)
            segmentStart = index
        }

        // Very long sessions should not produce a confetti of regions.
        if cuts.count > maximumSegments {
            let strongest = cuts.dropFirst()
                .sorted { boundaryScores[$0] > boundaryScores[$1] }
                .prefix(maximumSegments - 1)
                .sorted()
            cuts = [0] + strongest
        }

        var segments: [ConversationSegment] = []
        segments.reserveCapacity(cuts.count)
        for (ordinal, start) in cuts.enumerated() {
            let end = ordinal + 1 < cuts.count ? cuts[ordinal + 1] : units.count
            segments.append(makeSegment(thread: thread, units: units, range: start..<end, ordinal: ordinal))
        }
        return segments
    }

    // MARK: - Helpers

    private func makeSegment(
        thread: ConversationThread,
        units: [Unit],
        range: Range<Int>,
        ordinal: Int
    ) -> ConversationSegment {
        let slice = units[range]
        return ConversationSegment(
            id: "\(thread.id)#\(ordinal)",
            threadID: thread.id,
            startMessageIndex: slice.first?.start ?? 0,
            endMessageIndex: slice.last?.end ?? thread.messages.count,
            startedAt: slice.compactMap(\.startedAt).min(),
            endedAt: slice.compactMap(\.endedAt).max(),
            text: slice.map(\.text).joined(separator: "\n"),
            characterCount: slice.reduce(0) { $0 + $1.characterCount },
            userCharacterCount: slice.reduce(0) { $0 + $1.userCharacterCount },
            turnCount: slice.count
        )
    }

    private func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(union)
    }

    private func timeGap(previous: Date?, next: Date?) -> Double {
        guard let previous, let next else { return 0 }
        let hours = max(0, next.timeIntervalSince(previous)) / 3_600
        return min(1, log1p(hours) / log1p(24))
    }

    private static let cues: [String] = [
        "let's switch", "let us switch", "let's talk about", "let us talk about",
        "moving on", "on a different note", "different topic", "another topic",
        "next topic", "new topic", "now let's", "now let us", "switch to",
        "turn to", "separate question", "unrelated question", "second question",
        "andere frage", "nebenbei", "jetzt geht", "jetzt zum", "wechseln wir",
        "naechstes thema", "nächstes thema", "übrigens", "uebrigens", "separat"
    ]

    private func cueStrength(_ text: String) -> Double {
        let lower = text.lowercased()
        guard !lower.isEmpty else { return 0 }
        if lower.contains("\n#") { return 1 }
        for cue in Self.cues where lower.contains(cue) {
            return 1
        }
        return 0
    }
}
