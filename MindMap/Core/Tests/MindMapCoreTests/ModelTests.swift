import XCTest
@testable import MindMapCore

// MARK: - Provider

final class ProviderTests: XCTestCase {

    func testIdentityAndLabels() {
        XCTAssertEqual(Provider.chatgpt.id, "chatgpt")
        XCTAssertEqual(Provider.chatgpt.displayName, "ChatGPT")
        XCTAssertEqual(Provider.chatgpt.shortName, "GPT")
        XCTAssertEqual(Provider.gemini.shortName, "GEM")
        XCTAssertEqual(Provider.claude.shortName, "CLD")
        XCTAssertEqual(Provider.opencode.shortName, "OPC")
        XCTAssertEqual(Provider.other.shortName, "OTH")
        XCTAssertEqual(Provider.allCases.map(\.order), [0, 1, 2, 3, 4])
        XCTAssertEqual(Provider.allCases.map(\.displayName), ["ChatGPT", "Gemini", "Claude", "OpenCode", "Other"])
    }

    func testParsingAliases() {
        XCTAssertEqual(Provider.parse("chatgpt"), .chatgpt)
        XCTAssertEqual(Provider.parse("ChatGPT"), .chatgpt)
        XCTAssertEqual(Provider.parse("OpenAI GPT"), .chatgpt)
        XCTAssertEqual(Provider.parse("gpt"), .chatgpt)
        XCTAssertEqual(Provider.parse("gemini"), .gemini)
        XCTAssertEqual(Provider.parse("Bard"), .gemini)
        XCTAssertEqual(Provider.parse("Google"), .gemini)
        XCTAssertEqual(Provider.parse("claude"), .claude)
        XCTAssertEqual(Provider.parse("Anthropic Claude"), .claude)
        XCTAssertEqual(Provider.parse("OpenCode"), .opencode)
        XCTAssertEqual(Provider.parse("  open code  "), .opencode)
        XCTAssertEqual(Provider.parse("mistral"), .other)
        XCTAssertEqual(Provider.parse(nil), .other)
        XCTAssertEqual(Provider.parse(""), .other)
        XCTAssertEqual(Provider.parse("   "), .other)
    }
}

// MARK: - Message role

final class MessageRoleTests: XCTestCase {

    func testLabelsAndPromptFlag() {
        XCTAssertEqual(MessageRole.user.label, "USER")
        XCTAssertEqual(MessageRole.assistant.label, "ASSISTANT")
        XCTAssertEqual(MessageRole.system.label, "SYSTEM")
        XCTAssertEqual(MessageRole.tool.label, "TOOL")
        XCTAssertTrue(MessageRole.user.isPrompt)
        XCTAssertFalse(MessageRole.assistant.isPrompt)
        XCTAssertFalse(MessageRole.system.isPrompt)
    }

    func testParsingAliases() {
        for raw in ["user", "human", "prompt", "USER"] {
            XCTAssertEqual(MessageRole.parse(raw), .user, raw)
        }
        for raw in ["assistant", "ai", "model", "bot"] {
            XCTAssertEqual(MessageRole.parse(raw), .assistant, raw)
        }
        XCTAssertEqual(MessageRole.parse("system"), .system)
        XCTAssertEqual(MessageRole.parse("tool"), .tool)
        XCTAssertEqual(MessageRole.parse("function"), .tool)
        XCTAssertNil(MessageRole.parse("narrator"))
        XCTAssertNil(MessageRole.parse(nil))
    }
}

// MARK: - ChatMessage

final class ChatMessageTests: XCTestCase {

    func testTokenCountSumsKnownKinds() {
        let message = ChatMessage(
            id: "m",
            role: .assistant,
            text: "hi",
            inputTokens: 10,
            outputTokens: 20,
            cachedTokens: 5
        )
        XCTAssertEqual(message.tokenCount, 35)
        XCTAssertEqual(ChatMessage(id: "m", role: .user, text: "hi").tokenCount, 0)
    }

    func testHashableAndCodable() throws {
        let message = ChatMessage(
            id: "m",
            role: .user,
            text: "hello",
            timestamp: Date(timeIntervalSince1970: 100),
            cost: 0.5
        )
        XCTAssertEqual(message, message)
        let data = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(ChatMessage.self, from: data), message)
    }
}

// MARK: - ConversationThread

final class ConversationThreadTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func thread(
        messages: [ChatMessage] = [],
        cost: Double? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cachedTokens: Int? = nil,
        sourceURL: URL? = nil,
        id: String = "chatgpt:thread",
        provider: Provider = .chatgpt
    ) -> ConversationThread {
        ConversationThread(
            id: id,
            provider: provider,
            title: "A title",
            createdAt: start,
            messages: messages,
            model: "model",
            sourceURL: sourceURL,
            cost: cost,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens
        )
    }

    func testUpdatedAtDefaultsToLastMessage() {
        let messages = [
            ChatMessage(id: "1", role: .user, text: "one", timestamp: start),
            ChatMessage(id: "2", role: .assistant, text: "two", timestamp: start.addingTimeInterval(50))
        ]
        XCTAssertEqual(thread(messages: messages).updatedAt, start.addingTimeInterval(50))
        XCTAssertEqual(thread().updatedAt, start)
        let explicit = ConversationThread(
            id: "t",
            provider: .other,
            title: "t",
            createdAt: start,
            updatedAt: start.addingTimeInterval(90),
            messages: messages
        )
        XCTAssertEqual(explicit.updatedAt, start.addingTimeInterval(90))
    }

    func testCounts() {
        let messages = [
            ChatMessage(id: "1", role: .user, text: "one two three", timestamp: start),
            ChatMessage(id: "2", role: .assistant, text: "four five", timestamp: start),
            ChatMessage(id: "3", role: .user, text: "six", timestamp: start)
        ]
        let value = thread(messages: messages)
        XCTAssertEqual(value.messageCount, 3)
        XCTAssertEqual(value.userMessageCount, 2)
        XCTAssertEqual(value.characterCount, "one two three".count + "four five".count + "six".count)
        XCTAssertEqual(value.wordCount, 6)
    }

    func testCostSemantics() {
        let messages = [
            ChatMessage(id: "1", role: .user, text: "one"),
            ChatMessage(id: "2", role: .assistant, text: "two", cost: 0.25),
            ChatMessage(id: "3", role: .assistant, text: "three", cost: 0.25)
        ]
        let withoutSessionCost = thread(messages: messages)
        XCTAssertTrue(withoutSessionCost.hasCostData)
        XCTAssertEqual(withoutSessionCost.totalCost, 0.5, accuracy: 0.0001)
        XCTAssertEqual(withoutSessionCost.costPerMessage, 0.5 / 3, accuracy: 0.0001)

        let withSessionCost = thread(messages: messages, cost: 3)
        XCTAssertEqual(withSessionCost.totalCost, 3, accuracy: 0.0001)
        XCTAssertEqual(withSessionCost.costPerMessage, 1, accuracy: 0.0001)

        XCTAssertFalse(thread(messages: [ChatMessage(id: "1", role: .user, text: "x")]).hasCostData)
        XCTAssertTrue(thread(cost: 0).hasCostData, "a reported zero still counts as cost data")
        XCTAssertEqual(thread(cost: 0).totalCost, 0, accuracy: 0.0001)
        XCTAssertEqual(thread().costPerMessage, 0, accuracy: 0.0001)
    }

    func testTokenCountPrefersSessionTotals() {
        let messages = [
            ChatMessage(id: "1", role: .assistant, text: "x", inputTokens: 10, outputTokens: 5)
        ]
        let sessionTotals = thread(messages: messages, inputTokens: 100, outputTokens: 50, cachedTokens: 10)
        XCTAssertEqual(sessionTotals.tokenCount, 160)
        XCTAssertEqual(thread(messages: messages).tokenCount, 15)
        XCTAssertEqual(thread(inputTokens: 7).tokenCount, 7)
    }

    func testPreviewPrefersFirstUserPrompt() {
        let messages = [
            ChatMessage(id: "1", role: .assistant, text: "assistant first"),
            ChatMessage(id: "2", role: .user, text: "the real prompt"),
            ChatMessage(id: "3", role: .user, text: "later question")
        ]
        XCTAssertEqual(thread(messages: messages).preview, "the real prompt")
        XCTAssertEqual(thread(messages: [ChatMessage(id: "1", role: .assistant, text: "only")]).preview, "only")
        XCTAssertEqual(thread().preview, "")
        let long = String(repeating: "a", count: 200)
        let preview = thread(messages: [ChatMessage(id: "1", role: .user, text: long)]).preview
        XCTAssertEqual(preview.count, 181)
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    func testDeepLink() {
        let source = URL(string: "https://example.com/thread")!
        XCTAssertEqual(thread(sourceURL: source).deepLink, source)

        let uuid = "5f0f0c2e-1f47-4f8e-9a3a-1d2c3b4a5e6f"
        XCTAssertEqual(thread(id: "chatgpt:\(uuid)").deepLink?.absoluteString, "https://chatgpt.com/c/\(uuid)")
        XCTAssertEqual(thread(id: "claude:\(uuid)", provider: .claude).deepLink?.absoluteString, "https://claude.ai/chat/\(uuid)")
        XCTAssertNil(thread(id: "chatgpt:short").deepLink)
        XCTAssertNil(thread(id: "chatgpt:abcdefghijklmnopqrstuvwx").deepLink)
        XCTAssertNil(thread(id: "opencode:abc", provider: .opencode).deepLink)
        XCTAssertNil(thread(id: "gemini:abc", provider: .gemini).deepLink)
    }

    func testDateRange() {
        XCTAssertNil(thread().dateRange)
        let messages = [
            ChatMessage(id: "1", role: .user, text: "a", timestamp: start.addingTimeInterval(10)),
            ChatMessage(id: "2", role: .assistant, text: "b", timestamp: start),
            ChatMessage(id: "3", role: .user, text: "c")
        ]
        XCTAssertEqual(thread(messages: messages).dateRange, start...start.addingTimeInterval(10))
    }

    func testCodableRoundTrip() throws {
        let value = thread(
            messages: [ChatMessage(id: "1", role: .user, text: "hello", timestamp: start)],
            cost: 1.5,
            inputTokens: 3,
            outputTokens: 4,
            cachedTokens: 5,
            sourceURL: URL(string: "https://example.com")
        )
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ConversationThread.self, from: data), value)
    }
}

// MARK: - ThreadLibrary

final class ThreadLibraryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func makeThread(
        id: String,
        provider: Provider = .chatgpt,
        updatedAt: Date? = nil,
        messages: [ChatMessage] = [],
        isDemo: Bool = false,
        cost: Double? = nil
    ) -> ConversationThread {
        ConversationThread(
            id: id,
            provider: provider,
            title: id,
            createdAt: now,
            updatedAt: updatedAt,
            messages: messages,
            isDemo: isDemo,
            cost: cost
        )
    }

    func testEmptyLibrary() {
        XCTAssertEqual(ThreadLibrary.empty.threads.count, 0)
        XCTAssertEqual(ThreadLibrary.empty.demoThreadCount, 0)
        XCTAssertFalse(ThreadLibrary.empty.hasDemoData)
        XCTAssertNil(ThreadLibrary.empty.earliestDate)
        XCTAssertNil(ThreadLibrary.empty.latestDate)
        XCTAssertEqual(ThreadLibrary.empty.messageCount, 0)
        XCTAssertEqual(ThreadLibrary.empty.totalCost, 0)
        XCTAssertEqual(ThreadLibrary.empty.costThreadCount, 0)
    }

    func testAggregates() {
        let library = ThreadLibrary(threads: [
            makeThread(
                id: "a",
                provider: .chatgpt,
                updatedAt: now.addingTimeInterval(20),
                messages: [ChatMessage(id: "1", role: .user, text: "x")],
                cost: 1
            ),
            makeThread(
                id: "b",
                provider: .gemini,
                updatedAt: now.addingTimeInterval(10),
                messages: [ChatMessage(id: "2", role: .user, text: "y")],
                isDemo: true
            ),
            makeThread(id: "c", provider: .gemini, updatedAt: now.addingTimeInterval(30))
        ])
        XCTAssertEqual(library.demoThreadCount, 1)
        XCTAssertTrue(library.hasDemoData)
        XCTAssertEqual(library.providerCounts[.chatgpt], 1)
        XCTAssertEqual(library.providerCounts[.gemini], 2)
        XCTAssertNil(library.providerCounts[.claude])
        XCTAssertEqual(library.earliestDate, now)
        XCTAssertEqual(library.latestDate, now.addingTimeInterval(30))
        XCTAssertEqual(library.messageCount, 2)
        XCTAssertEqual(library.totalCost, 1, accuracy: 0.0001)
        XCTAssertEqual(library.costThreadCount, 1)
    }

    func testRemoveDemoData() {
        var library = ThreadLibrary(threads: [
            makeThread(id: "demo", isDemo: true),
            makeThread(id: "real")
        ])
        library.removeDemoData()
        XCTAssertEqual(library.threads.map(\.id), ["real"])
        XCTAssertFalse(library.hasDemoData)
    }

    func testMergeAddsUpdatesAndSorts() {
        let oldDate = now.addingTimeInterval(-100)
        let original = makeThread(id: "existing", updatedAt: oldDate, messages: [])
        var library = ThreadLibrary(threads: [original])

        let newer = makeThread(
            id: "existing",
            updatedAt: now,
            messages: [ChatMessage(id: "1", role: .user, text: "new")]
        )
        let added = makeThread(id: "fresh", updatedAt: now.addingTimeInterval(10))
        let result = library.merge([newer, added])

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(library.threads.count, 2)
        XCTAssertEqual(library.threads.map(\.id), ["fresh", "existing"], "sorted by updatedAt descending")
        XCTAssertEqual(library.threads.first { $0.id == "existing" }?.messages.count, 1)
    }

    func testMergeKeepsRicherOrNewerCopy() {
        let rich = makeThread(
            id: "rich",
            updatedAt: now,
            messages: [
                ChatMessage(id: "1", role: .user, text: "a"),
                ChatMessage(id: "2", role: .assistant, text: "b")
            ]
        )
        var library = ThreadLibrary(threads: [rich])

        let older = makeThread(
            id: "rich",
            updatedAt: now.addingTimeInterval(-100),
            messages: [ChatMessage(id: "1", role: .user, text: "only")]
        )
        library.merge([older])
        XCTAssertEqual(library.threads.count, 1)
        XCTAssertEqual(library.threads[0].messages.count, 2, "older copy does not replace a richer one")

        let longer = makeThread(
            id: "rich",
            updatedAt: now.addingTimeInterval(-200),
            messages: [
                ChatMessage(id: "1", role: .user, text: "a"),
                ChatMessage(id: "2", role: .assistant, text: "b"),
                ChatMessage(id: "3", role: .user, text: "c")
            ]
        )
        let result = library.merge([longer])
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(library.threads[0].messages.count, 3, "more content still wins")
    }

    func testMergeHandlesDuplicateIDsInsideBatch() {
        var library = ThreadLibrary()
        let first = makeThread(id: "dup", updatedAt: now, messages: [ChatMessage(id: "1", role: .user, text: "a")])
        let second = makeThread(id: "dup", updatedAt: now, messages: [
            ChatMessage(id: "1", role: .user, text: "a"),
            ChatMessage(id: "2", role: .assistant, text: "b")
        ])
        let result = library.merge([first, second])
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(library.threads.count, 1)
        XCTAssertEqual(library.threads[0].messages.count, 2)
    }

    func testMergeEmptyInput() {
        var library = ThreadLibrary(threads: [makeThread(id: "a")])
        let result = library.merge([])
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(library.threads.count, 1)
    }

    func testCodableRoundTrip() throws {
        let library = ThreadLibrary(
            threads: [makeThread(id: "a", provider: .claude)],
            lastImport: now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ThreadLibrary.self, from: encoder.encode(library))
        XCTAssertEqual(decoded.threads.count, 1)
        XCTAssertEqual(decoded.threads[0].provider, .claude)
        XCTAssertEqual(decoded.lastImport, now)
    }
}
