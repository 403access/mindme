import XCTest
@testable import MindMapCore

// MARK: - Keyword extraction

final class KeywordExtractorTests: XCTestCase {

    func testTokenizationRules() {
        XCTAssertEqual(KeywordExtractor.tokenize("The model and the agent"), ["agent"])
        XCTAssertEqual(
            KeywordExtractor.tokenize("SwiftUI Canvas performance"),
            ["swiftui", "canvas", "performance"]
        )
        XCTAssertEqual(KeywordExtractor.tokenize("ab abc"), ["abc"], "tokens shorter than three characters are dropped")
        XCTAssertEqual(KeywordExtractor.tokenize("123 456 !!!"), [])
        XCTAssertEqual(KeywordExtractor.tokenize("gpt5 123abc"), ["gpt5", "123abc"])
        XCTAssertEqual(KeywordExtractor.tokenize("data code model test testing"), [], "weak AI terms are filtered")
        XCTAssertEqual(KeywordExtractor.tokenize("hello_world"), [], "stopwords and weak terms are filtered")
    }

    func testSingularization() {
        XCTAssertEqual(KeywordExtractor.tokenize("agents"), ["agent"])
        XCTAssertEqual(KeywordExtractor.tokenize("varieties"), ["variety"])
        XCTAssertEqual(KeywordExtractor.tokenize("tomatoes"), ["tomato"])
        XCTAssertEqual(KeywordExtractor.tokenize("churches"), ["church"])
        XCTAssertEqual(KeywordExtractor.tokenize("boxes"), ["box"])
        XCTAssertEqual(KeywordExtractor.tokenize("classes"), ["classe"])
        XCTAssertEqual(KeywordExtractor.tokenize("analysis"), ["analysis"])
        XCTAssertEqual(KeywordExtractor.tokenize("status"), ["status"])
        XCTAssertEqual(KeywordExtractor.tokenize("chaos"), ["chaos"])
        XCTAssertEqual(KeywordExtractor.tokenize("physics"), ["physics"])
    }

    func testTokenLengthBounds() {
        XCTAssertEqual(KeywordExtractor.tokenize(String(repeating: "a", count: 32)).count, 1)
        XCTAssertEqual(KeywordExtractor.tokenize(String(repeating: "a", count: 33)).count, 0)
        XCTAssertEqual(KeywordExtractor.tokenize("ab").count, 0)
        XCTAssertEqual(KeywordExtractor.tokenize("abc").count, 1)
    }

    private func thread(id: String, title: String, texts: [String], role: MessageRole = .user) -> ConversationThread {
        ConversationThread(
            id: id,
            provider: .other,
            title: title,
            createdAt: Date(timeIntervalSince1970: 0),
            messages: texts.enumerated().map { index, text in
                ChatMessage(id: "\(id)-\(index)", role: role, text: text)
            }
        )
    }

    func testEmptyIndex() {
        let index = KeywordExtractor.buildIndex(threads: [])
        XCTAssertTrue(index.idf.isEmpty)
        XCTAssertTrue(index.keywordsByThread.isEmpty)
        XCTAssertTrue(index.documentFrequency.isEmpty)
        XCTAssertTrue(index.keywords(for: "missing").isEmpty)
    }

    func testDocumentFrequencyAndIDF() {
        let threads = [
            thread(id: "1", title: "", texts: ["alpha"]),
            thread(id: "2", title: "", texts: ["alpha beta"]),
            thread(id: "3", title: "", texts: ["alpha beta gamma"])
        ]
        let index = KeywordExtractor.buildIndex(threads: threads)
        XCTAssertEqual(index.documentFrequency["alpha"], 3)
        XCTAssertEqual(index.documentFrequency["beta"], 2)
        XCTAssertEqual(index.documentFrequency["gamma"], 1)
        XCTAssertGreaterThan(index.idf["gamma"] ?? 0, index.idf["beta"] ?? 0)
        XCTAssertGreaterThan(index.idf["beta"] ?? 0, index.idf["alpha"] ?? 0)
    }

    func testLimitPerThreadAndKeywordLimit() {
        let threads = [
            thread(id: "1", title: "alpha beta gamma delta", texts: ["epsilon zeta eta theta"])
        ]
        let limited = KeywordExtractor.buildIndex(threads: threads, limitPerThread: 2)
        XCTAssertEqual(limited.keywords(for: "1").count, 2)

        let direct = KeywordExtractor.keywords(for: threads[0], idf: [:], limit: 3)
        XCTAssertEqual(direct.count, 3)
        XCTAssertTrue(direct.allSatisfy { $0.score > 0 })
    }

    func testTitleTermsOutrankRepeatedBodyTerms() throws {
        let titled = thread(id: "titled", title: "Terraform", texts: ["Tell me about deployments."])
        let repeated = thread(
            id: "repeated",
            title: "Deployment",
            texts: ["Terraform terraform terraform terraform terraform terraform"]
        )
        let index = KeywordExtractor.buildIndex(threads: [titled, repeated])
        let keywords = index.keywords(for: "titled")
        XCTAssertEqual(keywords.first?.term, "terraform")
        XCTAssertGreaterThan(keywords.first?.score ?? 0, 0)
    }

    func testUserTextWeighsMoreThanAssistantText() {
        let value = ConversationThread(
            id: "t",
            provider: .other,
            title: "",
            createdAt: Date(timeIntervalSince1970: 0),
            messages: [
                ChatMessage(id: "1", role: .user, text: "alpha"),
                ChatMessage(id: "2", role: .assistant, text: "beta")
            ]
        )
        let keywords = KeywordExtractor.keywords(for: value, idf: [:], limit: 2)
        XCTAssertEqual(keywords.map(\.term), ["alpha", "beta"])
        XCTAssertGreaterThan(keywords[0].score, keywords[1].score)
    }

    func testDeterministicTieBreakIsAlphabetical() {
        let value = thread(id: "t", title: "", texts: ["beta alpha"])
        let keywords = KeywordExtractor.keywords(for: value, idf: [:], limit: 2)
        XCTAssertEqual(keywords.map(\.term), ["alpha", "beta"])
    }

    func testSystemAndToolMessagesAreIgnored() {
        let value = ConversationThread(
            id: "t",
            provider: .other,
            title: "",
            createdAt: Date(timeIntervalSince1970: 0),
            messages: [
                ChatMessage(id: "1", role: .system, text: "secret system vocabulary"),
                ChatMessage(id: "2", role: .tool, text: "hidden tool output")
            ]
        )
        XCTAssertTrue(KeywordExtractor.keywords(for: value, idf: [:]).isEmpty)
    }

    func testRawTextKeywords() {
        let keywords = KeywordExtractor.keywords(inText: "alpha alpha beta", idf: ["alpha": 2, "beta": 1], limit: 2)
        XCTAssertEqual(keywords.map(\.term), ["alpha", "beta"])
        XCTAssertGreaterThan(keywords[0].score, keywords[1].score)
        XCTAssertEqual(KeywordExtractor.keywords(inText: "", idf: [:]).count, 0)
        XCTAssertEqual(KeywordExtractor.keywords(inText: "alpha", idf: [:], limit: 0).count, 0)
    }

    func testPrettyLabel() {
        XCTAssertEqual(KeywordExtractor.prettyLabel("swift"), "Swift")
        XCTAssertEqual(KeywordExtractor.prettyLabel("SWIFT"), "SWIFT")
        XCTAssertEqual(KeywordExtractor.prettyLabel(""), "")
    }
}

// MARK: - Topic clustering

final class TopicClustererTests: XCTestCase {

    private func thread(id: String, title: String, text: String) -> ConversationThread {
        ConversationThread(
            id: id,
            provider: .other,
            title: title,
            createdAt: Date(timeIntervalSince1970: 0),
            messages: [ChatMessage(id: "\(id)-m", role: .user, text: text)]
        )
    }

    private func clusters(
        _ threads: [ConversationThread],
        maxTopics: Int = 9,
        minimumSize: Int = 2
    ) -> [TopicCluster] {
        let index = KeywordExtractor.buildIndex(threads: threads)
        return TopicClusterer.clusters(
            threads: threads,
            index: index,
            maxTopics: maxTopics,
            minimumSize: minimumSize
        )
    }

    func testRequiresAtLeastTwoThreads() {
        let single = thread(id: "1", title: "Alpha", text: "kubernetes")
        XCTAssertTrue(clusters([single]).isEmpty)
        XCTAssertTrue(clusters([]).isEmpty)
    }

    func testSharedKeywordBecomesCluster() throws {
        let threads = [
            thread(id: "1", title: "Alpha", text: "swift cluster"),
            thread(id: "2", title: "Beta", text: "swift deployment"),
            thread(id: "3", title: "Gamma", text: "javascript")
        ]
        let result = clusters(threads)
        let swift = try XCTUnwrap(result.first { $0.label == "swift" })
        XCTAssertEqual(swift.id, "topic:swift")
        XCTAssertEqual(swift.threadIDs, ["1", "2"])
        XCTAssertGreaterThan(swift.score, 0)
        XCTAssertEqual(swift.colorSeed, 0)
    }

    func testMinimumSizeFiltersSmallTopics() {
        let threads = [
            thread(id: "1", title: "Alpha", text: "kubernetes"),
            thread(id: "2", title: "Beta", text: "kubernetes")
        ]
        XCTAssertTrue(clusters(threads, minimumSize: 3).isEmpty)
    }

    func testMaxTopicsCapsSelection() {
        let threads = [
            thread(id: "1", title: "One", text: "alpha"),
            thread(id: "2", title: "Two", text: "alpha"),
            thread(id: "3", title: "Three", text: "beta"),
            thread(id: "4", title: "Four", text: "beta"),
            thread(id: "5", title: "Five", text: "gamma"),
            thread(id: "6", title: "Six", text: "gamma")
        ]
        let result = clusters(threads, maxTopics: 2)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.label), ["alpha", "beta"])
    }

    func testNearDuplicateTopicsAreDominated() {
        let threads = [
            thread(id: "1", title: "One", text: "swift swiftui"),
            thread(id: "2", title: "Two", text: "swift swiftui")
        ]
        let result = clusters(threads)
        XCTAssertEqual(result.map(\.label), ["swift"])
    }

    func testClustersSortBySizeThenLabelAndAssignColorSeeds() {
        let threads = [
            thread(id: "1", title: "One", text: "alpha"),
            thread(id: "2", title: "Two", text: "alpha"),
            thread(id: "3", title: "Three", text: "alpha"),
            thread(id: "4", title: "Four", text: "beta"),
            thread(id: "5", title: "Five", text: "beta")
        ]
        let result = clusters(threads)
        XCTAssertEqual(result.map(\.label), ["alpha", "beta"])
        XCTAssertEqual(result[0].threadIDs.count, 3)
        XCTAssertEqual(result[1].threadIDs.count, 2)
        XCTAssertEqual(result.map(\.colorSeed), [0, 1])
        XCTAssertEqual(result[0].id, "topic:alpha")
        XCTAssertTrue(result[1].threadIDs == result[1].threadIDs.sorted(), "thread IDs are sorted")
    }

    func testClusteringIsDeterministic() {
        let threads = [
            thread(id: "1", title: "Alpha", text: "swift deployment"),
            thread(id: "2", title: "Beta", text: "swift service"),
            thread(id: "3", title: "Gamma", text: "javascript canvas")
        ]
        XCTAssertEqual(clusters(threads), clusters(threads))
    }
}
