import XCTest
@testable import MindMapCore

// MARK: - Fixtures

private let baseDate = Date(timeIntervalSince1970: 1_780_000_000)

private func makeThread(
    id: String = "thread",
    title: String = "Project notes",
    exchanges: [(String, String)],
    start: Date = baseDate
) -> ConversationThread {
    var messages: [ChatMessage] = []
    for (offset, exchange) in exchanges.enumerated() {
        let date = start.addingTimeInterval(Double(offset) * 600)
        messages.append(ChatMessage(
            id: "\(id)-u\(offset)",
            role: .user,
            text: exchange.0,
            timestamp: date
        ))
        messages.append(ChatMessage(
            id: "\(id)-a\(offset)",
            role: .assistant,
            text: exchange.1,
            timestamp: date.addingTimeInterval(30)
        ))
    }
    return ConversationThread(
        id: id,
        provider: .chatgpt,
        title: title,
        createdAt: start,
        messages: messages
    )
}

private func techThread(id: String = "tech") -> ConversationThread {
    makeThread(
        id: id,
        title: "Database migration for the Swift API",
        exchanges: [
            ("The Swift API endpoint fails after the database schema migration. I need to debug the backend and compile a fix.",
             "Check the migration, inspect the query, and read the server logs. Refactor the endpoint and add a test."),
            ("The server still returns an error when the schema is migrated. Which database function should I change?",
             "Trace the SQL query, then update the migration and rerun the test suite.")
        ]
    )
}

private func legalThread(id: String = "legal") -> ConversationThread {
    makeThread(
        id: id,
        title: "NDA and liability review",
        exchanges: [
            ("Please review the contract clause about liability and the NDA. The termination terms and jurisdiction look wrong.",
             "The agreement's indemnity clause and breach terms need counsel; check the signature block."),
            ("Can the contract limit liability for the vendor and still keep the NDA enforceable?",
             "A clause can cap liability, but the agreement must state the jurisdiction and termination terms clearly.")
        ]
    )
}

private struct FixedEmbedder: TopicEmbeddingProvider {
    let id = "fixed-16-v1"
    let dimensions = 16
    func embed(_ text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dimensions)
        vector[0] = 1
        return vector
    }
}

// MARK: - Segmentation units

final class ConversationSegmenterTests: XCTestCase {

    private let segmenter = ConversationSegmenter()

    func testUnitsSkipSystemAndToolAndMergeAssistantReplies() {
        let thread = ConversationThread(
            id: "t",
            provider: .other,
            title: "",
            createdAt: baseDate,
            messages: [
                ChatMessage(id: "0", role: .system, text: "system", timestamp: baseDate),
                ChatMessage(id: "1", role: .user, text: "q1", timestamp: baseDate.addingTimeInterval(10)),
                ChatMessage(id: "2", role: .assistant, text: "a1", timestamp: baseDate.addingTimeInterval(20)),
                ChatMessage(id: "3", role: .tool, text: "tool", timestamp: baseDate.addingTimeInterval(30)),
                ChatMessage(id: "4", role: .assistant, text: "a1b", timestamp: baseDate.addingTimeInterval(40)),
                ChatMessage(id: "5", role: .user, text: "q2", timestamp: baseDate.addingTimeInterval(50)),
                ChatMessage(id: "6", role: .assistant, text: "a2", timestamp: baseDate.addingTimeInterval(60))
            ]
        )
        let units = segmenter.units(for: thread)
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[0].start, 1)
        XCTAssertEqual(units[0].end, 5)
        XCTAssertEqual(units[0].text, "q1\na1\na1b")
        XCTAssertEqual(units[0].userText, "q1")
        XCTAssertEqual(units[0].userCharacterCount, 2)
        XCTAssertEqual(units[0].characterCount, 7, "newlines joining parts are not counted")
        XCTAssertEqual(units[0].startedAt, baseDate.addingTimeInterval(10))
        XCTAssertEqual(units[0].endedAt, baseDate.addingTimeInterval(40))
        XCTAssertTrue(units[0].tokens.contains("a1b"))
        XCTAssertEqual(units[1].start, 5)
        XCTAssertEqual(units[1].end, 7)
        XCTAssertEqual(units[1].text, "q2\na2")
    }

    func testEmptyThreadProducesNoSegments() {
        let thread = ConversationThread(
            id: "empty",
            provider: .other,
            title: "",
            createdAt: baseDate,
            messages: []
        )
        XCTAssertTrue(segmenter.segment(thread).isEmpty)
    }

    func testSingleExchangeProducesOneSegmentWithMetadata() {
        let thread = makeThread(exchanges: [("Only question", "Only answer")])
        let segments = segmenter.segment(thread)
        XCTAssertEqual(segments.count, 1)
        let segment = segments[0]
        XCTAssertEqual(segment.id, "thread#0")
        XCTAssertEqual(segment.threadID, "thread")
        XCTAssertEqual(segment.startMessageIndex, 0)
        XCTAssertEqual(segment.endMessageIndex, 2)
        XCTAssertEqual(segment.text, "Only question\nOnly answer")
        XCTAssertEqual(segment.turnCount, 1)
        XCTAssertEqual(segment.userCharacterCount, "Only question".count)
        XCTAssertEqual(segment.characterCount, 24, "the joining newline is not counted")
        XCTAssertEqual(segment.startedAt, baseDate)
        XCTAssertEqual(segment.endedAt, baseDate.addingTimeInterval(30))
    }

    func testCueSplitsSegmentsAndKeepsThemContiguous() {
        let thread = makeThread(exchanges: [
            ("The Swift API endpoint fails after the database migration. Debug the backend and compile a fix.",
             "Check the migration and read the logs."),
            ("The server returns an error when the schema is migrated. Which database function should I change?",
             "Trace the SQL query and rerun the tests."),
            ("Now let's switch to the contract and the NDA. The liability clause needs review.",
             "The agreement's indemnity clause needs counsel."),
            ("Can the contract limit liability and keep the NDA enforceable?",
             "A clause can cap liability but must state the jurisdiction.")
        ])
        let segments = segmenter.segment(thread)
        XCTAssertGreaterThanOrEqual(segments.count, 2)
        XCTAssertEqual(segments.first?.startMessageIndex, 0)
        XCTAssertEqual(segments.last?.endMessageIndex, thread.messages.count)
        for index in 1..<segments.count {
            XCTAssertEqual(segments[index - 1].endMessageIndex, segments[index].startMessageIndex)
        }
        XCTAssertEqual(segments.map(\.id), (0..<segments.count).map { "thread#\($0)" })
    }

    func testMaximumSegmentsCapsOutput() {
        let exchanges: [(String, String)] = (0..<12).map { index in
            let topic = ["database migration", "contract liability", "roadmap pricing"][index % 3]
            return ("Now let's switch to a different topic: \(topic) number \(index).",
                    "Answer about \(topic) number \(index).")
        }
        let thread = makeThread(exchanges: exchanges)
        var custom = ConversationSegmenter()
        custom.maximumSegments = 3
        let segments = custom.segment(thread)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.last?.endMessageIndex, thread.messages.count)
    }

    func testMinimumSegmentTurnsIsRespectedForLongThreads() {
        let exchanges: [(String, String)] = (0..<8).map { index in
            let topic = ["database migration", "contract liability"][index % 2]
            return ("Let's switch to \(topic) number \(index).", "Answer \(index).")
        }
        let thread = makeThread(exchanges: exchanges)
        let segments = segmenter.segment(thread)
        XCTAssertGreaterThanOrEqual(segments.count, 1)
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.turnCount, 2)
        }
    }

    func testCustomEmbedderCanDisableVocabularyDrivenSplits() {
        let exchanges: [(String, String)] = [
            ("Alpha beta gamma delta.", "Epsilon zeta eta theta."),
            ("Alpha beta gamma delta.", "Epsilon zeta eta theta."),
            ("Alpha beta gamma delta.", "Epsilon zeta eta theta."),
            ("Alpha beta gamma delta.", "Epsilon zeta eta theta.")
        ]
        let thread = makeThread(exchanges: exchanges)
        let custom = ConversationSegmenter(embedder: FixedEmbedder())
        let segments = custom.segment(thread)
        XCTAssertEqual(segments.count, 1)
    }

    func testSegmentationIsDeterministic() {
        let thread = techThread()
        XCTAssertEqual(segmenter.segment(thread), segmenter.segment(thread))
    }
}

// MARK: - Embedding and classification

final class TopicClassifierTests: XCTestCase {

    func testHashingEmbedderDimensionsAndNormalization() {
        let small = HashingEmbedder(dimensions: 8)
        XCTAssertEqual(small.dimensions, 32, "dimensions have a floor")
        XCTAssertEqual(small.id, "hash-32-v1")

        let embedder = HashingEmbedder()
        XCTAssertEqual(embedder.dimensions, 256)
        XCTAssertEqual(embedder.id, "hash-256-v1")
        let first = embedder.embed("Swift database migration and schema")
        XCTAssertEqual(first, embedder.embed("Swift database migration and schema"))
        XCTAssertEqual(first.reduce(0) { $0 + $1 * $1 }, 1, accuracy: 0.0001)
        XCTAssertEqual(embedder.embed("   "), [Float](repeating: 0, count: 256))
        XCTAssertLessThan(
            TopicVector.dot(first, embedder.embed("contract liability NDA")),
            TopicVector.dot(first, first)
        )
    }

    func testVectorHelpers() {
        XCTAssertEqual(TopicVector.dot([1, 2, 3], [4, 5]), 14, accuracy: 0.0001)
        XCTAssertEqual(TopicVector.dot([], [1]), 0, accuracy: 0.0001)
        XCTAssertEqual(
            TopicVector.centroid([], dimensions: 3),
            [Float](repeating: 0, count: 3)
        )
        let centroid = TopicVector.centroid([[1, 0], [1, 0]], dimensions: 2)
        XCTAssertEqual(centroid[0], 1, accuracy: 0.0001)
        XCTAssertEqual(centroid[1], 0, accuracy: 0.0001)
        XCTAssertEqual(TopicVector.normalized([3, 4]), [0.6, 0.8])
        XCTAssertEqual(TopicVector.normalized([0, 0]), [0, 0])
    }

    func testDistributionIsSoftAndUsesLeafTopics() throws {
        let classifier = TopicClassifier(taxonomy: .default, embedder: HashingEmbedder())
        let distribution = classifier.distribution(for: techThread().messages.map(\.text).joined(separator: " "))
        XCTAssertFalse(distribution.isEmpty)
        XCTAssertEqual(distribution.values.reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(distribution.values.max() ?? 0, 0.5)
        for id in distribution.keys {
            let node = try XCTUnwrap(TopicTaxonomy.default.node(id: id))
            XCTAssertNotNil(node.parentID, "\(id) should be a leaf")
            XCTAssertTrue(TopicTaxonomy.default.children(of: id).isEmpty, "\(id) should have no children")
            XCTAssertFalse(node.isFallback)
        }
    }

    func testEmptyTextFallsBackToEmerging() {
        let classifier = TopicClassifier(taxonomy: .default, embedder: HashingEmbedder())
        XCTAssertEqual(classifier.distribution(for: ""), ["emerging": 1])
        XCTAssertEqual(classifier.distribution(for: "!!! ???"), ["emerging": 1])
    }

    func testBlendedInheritsPriorForFallbackSegments() {
        let classifier = TopicClassifier(taxonomy: .default, embedder: HashingEmbedder())
        let prior = ["technology/software": 1.0]
        XCTAssertEqual(classifier.blended("   ", with: prior, priorWeight: 0.1), prior)
        XCTAssertEqual(
            classifier.blended("   ", with: prior, priorWeight: 0),
            ["emerging": 1]
        )
        XCTAssertEqual(classifier.blended("   ", with: [:], priorWeight: 0.1), ["emerging": 1])
    }

    func testBlendedMixesSignalsAndCapsPriorWeight() {
        let classifier = TopicClassifier(taxonomy: .default, embedder: HashingEmbedder())
        let text = techThread().messages.map(\.text).joined(separator: " ")
        let prior = ["legal/contracts": 1.0]
        let blended = classifier.blended(text, with: prior, priorWeight: 2.0)
        XCTAssertEqual(blended.values.reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(blended["legal/contracts"] ?? 0, 0.5 + 0.0001, "prior weight is clamped to 0.5")
        XCTAssertGreaterThan(blended["technology/software"] ?? 0, 0)
    }

    func testEvidenceOnlyReturnsWordsFromThePrototype() {
        let classifier = TopicClassifier(taxonomy: .default, embedder: HashingEmbedder())
        let text = "Swift database migration and API debugging"
        let evidence = classifier.evidence(for: text, topicID: "technology/software", limit: 4)
        XCTAssertFalse(evidence.isEmpty)
        XCTAssertLessThanOrEqual(evidence.count, 4)
        XCTAssertTrue(evidence.allSatisfy { KeywordExtractor.tokenize(text).contains($0) })
        XCTAssertTrue(classifier.evidence(for: text, topicID: "missing/topic").isEmpty)
    }

    func testTaxonomyWithoutLeavesAlwaysFallsBack() {
        let taxonomy = TopicTaxonomy(nodes: [
            TopicNode(id: "emerging", label: "Emerging", isFallback: true)
        ])
        let classifier = TopicClassifier(taxonomy: taxonomy, embedder: HashingEmbedder())
        XCTAssertEqual(classifier.distribution(for: "anything at all"), ["emerging": 1])
    }
}

// MARK: - Viterbi smoothing

final class ViterbiTests: XCTestCase {

    func testEmptyInputReturnsEmptyPath() {
        XCTAssertTrue(TopicPipeline.viterbi([], taxonomy: .default).isEmpty)
        XCTAssertTrue(TopicPipeline.viterbi([[:]], taxonomy: .default).isEmpty)
    }

    func testSiblingSwitchIsCheap() {
        let path = TopicPipeline.viterbi(
            [
                ["technology/software": 0.9, "technology/ai": 0.1],
                ["technology/software": 0.05, "technology/ai": 0.95]
            ],
            taxonomy: .default
        )
        XCTAssertEqual(path, ["technology/software", "technology/ai"])
    }

    func testStrongCrossDomainEvidenceMovesThePath() {
        let path = TopicPipeline.viterbi(
            [
                ["technology/software": 0.9, "legal/contracts": 0.1],
                ["technology/software": 0.02, "legal/contracts": 0.98]
            ],
            taxonomy: .default
        )
        XCTAssertEqual(path, ["technology/software", "legal/contracts"])
    }

    func testWeakStraySegmentDoesNotTearTheRegionApart() {
        let path = TopicPipeline.viterbi(
            [
                ["technology/software": 0.75, "legal/contracts": 0.25],
                ["technology/software": 0.75, "legal/contracts": 0.25]
            ],
            taxonomy: .default
        )
        XCTAssertEqual(path, ["technology/software", "technology/software"])
    }
}

// MARK: - Pipeline

final class TopicPipelineTests: XCTestCase {

    func testEmptyLibraryProducesEmptyAnalysis() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let analysis = TopicPipeline().analyze(ThreadLibrary(), now: now)
        XCTAssertTrue(analysis.isEmpty)
        XCTAssertEqual(analysis.libraryHash, StableID.hex(""))
        XCTAssertEqual(analysis.updatedAt, now)
        XCTAssertEqual(analysis.version, TopicPipeline.pipelineVersion)
        XCTAssertEqual(analysis.embedderID, "hash-256-v1")
    }

    func testThreadWithoutMessagesFallsBack() {
        let thread = ConversationThread(
            id: "empty",
            provider: .other,
            title: "Empty",
            createdAt: baseDate,
            messages: []
        )
        let profile = TopicPipeline().analyze(thread)
        XCTAssertTrue(profile.segments.isEmpty)
        XCTAssertEqual(profile.primaryRegionID, "emerging")
        XCTAssertEqual(profile.primaryTopicID, "emerging")
        XCTAssertEqual(profile.regions.map(\.topicID), ["emerging"])
        XCTAssertEqual(profile.regions.first?.share ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(profile.topics.map(\.topicID), ["emerging"])
        XCTAssertEqual(profile.totalCost, 0, accuracy: 0.0001)
    }

    func testLibraryHashIsOrderIndependent() {
        let first = TopicPipeline().analyze(ThreadLibrary(threads: [techThread(), legalThread()]))
        let second = TopicPipeline().analyze(ThreadLibrary(threads: [legalThread(), techThread()]))
        XCTAssertEqual(first.libraryHash, second.libraryHash)
        XCTAssertEqual(first.profiles.keys.sorted(), ["legal", "tech"])
    }

    func testContentHashIncludesCostAndTokenFields() {
        let original = techThread()
        XCTAssertEqual(TopicPipeline.contentHash(for: original), TopicPipeline.contentHash(for: original))

        var costChanged = original
        costChanged.cost = 1
        XCTAssertNotEqual(TopicPipeline.contentHash(for: original), TopicPipeline.contentHash(for: costChanged))

        var tokensChanged = original
        tokensChanged.inputTokens = 10
        XCTAssertNotEqual(TopicPipeline.contentHash(for: original), TopicPipeline.contentHash(for: tokensChanged))

        var messageCostChanged = original
        messageCostChanged.messages[0].cost = 0.5
        XCTAssertNotEqual(TopicPipeline.contentHash(for: original), TopicPipeline.contentHash(for: messageCostChanged))

        var roleChanged = original
        roleChanged.messages[0].role = .assistant
        XCTAssertNotEqual(TopicPipeline.contentHash(for: original), TopicPipeline.contentHash(for: roleChanged))
    }

    func testCachedProfilesAreReused() {
        let library = ThreadLibrary(threads: [techThread(), legalThread()])
        let firstDate = Date(timeIntervalSince1970: 1_780_000_000)
        let first = TopicPipeline().analyze(library, now: firstDate)
        let secondDate = firstDate.addingTimeInterval(3_600)
        let second = TopicPipeline().analyze(library, cached: first, now: secondDate)

        XCTAssertEqual(second.profiles["tech"]?.analyzedAt, firstDate)
        XCTAssertEqual(second.profiles["legal"]?.analyzedAt, firstDate)
        XCTAssertEqual(second.updatedAt, secondDate)
        XCTAssertEqual(second.libraryHash, first.libraryHash)
    }

    func testCachedProfilesAreInvalidatedByVersionTaxonomyAndEmbedder() {
        let library = ThreadLibrary(threads: [techThread()])
        let firstDate = Date(timeIntervalSince1970: 1_780_000_000)
        let first = TopicPipeline().analyze(library, now: firstDate)
        let later = firstDate.addingTimeInterval(3_600)

        var badVersion = first
        badVersion.version += 1
        let versionResult = TopicPipeline().analyze(library, cached: badVersion, now: later)
        XCTAssertEqual(versionResult.profiles["tech"]?.analyzedAt, later)

        var taxonomy = TopicTaxonomy.default
        taxonomy.nodes[0].label = "Renamed Region"
        let taxonomyResult = TopicPipeline(taxonomy: taxonomy).analyze(library, cached: first, now: later)
        XCTAssertEqual(taxonomyResult.profiles["tech"]?.analyzedAt, later)
        XCTAssertEqual(taxonomyResult.taxonomy.nodes[0].label, "Renamed Region")

        let embedderResult = TopicPipeline(embedder: FixedEmbedder()).analyze(library, cached: first, now: later)
        XCTAssertEqual(embedderResult.profiles["tech"]?.analyzedAt, later)
        XCTAssertEqual(embedderResult.embedderID, "fixed-16-v1")
    }

    func testCachedProfileWithNoSegmentsIsRecomputed() {
        let library = ThreadLibrary(threads: [techThread()])
        let firstDate = Date(timeIntervalSince1970: 1_780_000_000)
        var cached = TopicPipeline().analyze(library, now: firstDate)
        cached.profiles["tech"]?.segments = []
        let later = firstDate.addingTimeInterval(60)
        let result = TopicPipeline().analyze(library, cached: cached, now: later)
        XCTAssertEqual(result.profiles["tech"]?.analyzedAt, later)
        XCTAssertFalse(result.profiles["tech"]?.segments.isEmpty ?? true)
    }

    func testProfileSharesAndCostsAreConsistent() {
        let thread = makeThread(exchanges: [
            ("The Swift API endpoint fails after the database migration. Debug the backend.",
             "Check the migration and the logs."),
            ("Now let's switch to the contract and the NDA. The liability clause needs review.",
             "The indemnity clause needs counsel.")
        ])
        let profile = TopicPipeline().analyze(thread)
        XCTAssertEqual(profile.regions.reduce(0) { $0 + $1.share }, 1, accuracy: 0.0001)
        XCTAssertEqual(profile.topics.reduce(0) { $0 + $1.share }, 1, accuracy: 0.0001)
        XCTAssertEqual(profile.regions.reduce(0) { $0 + $1.cost }, profile.totalCost, accuracy: 0.0001)
        XCTAssertEqual(profile.topics.reduce(0) { $0 + $1.cost }, profile.totalCost, accuracy: 0.0001)
        XCTAssertEqual(profile.primaryRegionID, profile.regions.first?.topicID)
        XCTAssertEqual(profile.primaryTopicID, profile.topics.first?.topicID)
        XCTAssertEqual(profile.segments.reduce(0) { $0 + $1.cost }, profile.totalCost, accuracy: 0.0001)
        XCTAssertEqual(profile.segments.first?.startMessageIndex, 0)
        XCTAssertEqual(profile.segments.last?.endMessageIndex, thread.messages.count)
    }

    func testSessionCostWithoutVisibleMessageCostsIsDistributedBySegmentWeight() {
        var thread = makeThread(exchanges: [
            ("The Swift API endpoint fails after the database migration. Debug the backend.",
             "Check the migration and the logs."),
            ("Now let's switch to the contract and the NDA. The liability clause needs review.",
             "The indemnity clause needs counsel.")
        ])
        thread.cost = 2
        let profile = TopicPipeline().analyze(thread)
        XCTAssertEqual(profile.totalCost, 2, accuracy: 0.0001)
        XCTAssertEqual(profile.segments.reduce(0) { $0 + $1.cost }, 2, accuracy: 0.0001)
        XCTAssertTrue(profile.segments.allSatisfy { $0.cost > 0 })
        XCTAssertEqual(profile.regions.reduce(0) { $0 + $1.cost }, 2, accuracy: 0.0001)
    }

    func testTokenTotalsUseSessionValuesOrMessageFallback() {
        var thread = techThread()
        thread.inputTokens = 100
        thread.outputTokens = 50
        thread.cachedTokens = 10
        let sessionProfile = TopicPipeline().analyze(thread)
        XCTAssertEqual(sessionProfile.inputTokens, 100)
        XCTAssertEqual(sessionProfile.outputTokens, 50)
        XCTAssertEqual(sessionProfile.cachedTokens, 10)

        var messageThread = techThread()
        messageThread.messages[0].inputTokens = 7
        messageThread.messages[1].outputTokens = 9
        messageThread.messages[1].cachedTokens = 3
        let messageProfile = TopicPipeline().analyze(messageThread)
        XCTAssertEqual(messageProfile.inputTokens, 7)
        XCTAssertEqual(messageProfile.outputTokens, 9)
        XCTAssertEqual(messageProfile.cachedTokens, 3)
    }

    func testConcurrentLibraryAnalysisMatchesSingleThreadAnalysis() {
        let threads = (0..<12).map { index in
            index % 2 == 0 ? techThread(id: "tech-\(index)") : legalThread(id: "legal-\(index)")
        }
        let library = ThreadLibrary(threads: threads)
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let analysis = TopicPipeline().analyze(library, now: now)
        XCTAssertEqual(analysis.profiles.count, threads.count)
        for thread in threads {
            let single = TopicPipeline().analyze(thread, now: now)
            XCTAssertEqual(analysis.profiles[thread.id]?.segments.map(\.topicID), single.segments.map(\.topicID))
            XCTAssertEqual(analysis.profiles[thread.id]?.regions, single.regions)
            XCTAssertEqual(analysis.profiles[thread.id]?.contentHash, single.contentHash)
        }
    }

    func testSharePercentagesAndSegmentTitles() {
        XCTAssertEqual(TopicShare(topicID: "a", label: "A", share: 0.126).percentage, 13)
        XCTAssertEqual(TopicShare(topicID: "a", label: "A", share: 0.124).percentage, 12)
        let segment = SegmentTopic(
            id: "s",
            startMessageIndex: 0,
            endMessageIndex: 1,
            startedAt: nil,
            endedAt: nil,
            topicID: "technology/software",
            topicLabel: "Software",
            regionID: "technology",
            regionLabel: "Technology",
            confidence: 0.8,
            keywords: ["swift"],
            characterCount: 10
        )
        XCTAssertEqual(segment.displayTitle, "Technology · Software")
    }
}
