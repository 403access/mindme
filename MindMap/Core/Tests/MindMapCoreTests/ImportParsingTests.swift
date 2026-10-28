import XCTest
@testable import MindMapCore

// MARK: - Result and error surfaces

final class ImportResultTests: XCTestCase {

    private func makeThread(id: String) -> ConversationThread {
        ConversationThread(
            id: id,
            provider: .other,
            title: id,
            createdAt: Date(timeIntervalSince1970: 0),
            messages: []
        )
    }

    func testSummaryCountsAndFormats() {
        XCTAssertEqual(ImportResult().summary, "0 threads from 0 files")
        XCTAssertEqual(
            ImportResult(threads: [makeThread(id: "a")], filesRead: 1, formats: ["chatgpt"]).summary,
            "1 threads from 1 file · chatgpt"
        )
        let two = ImportResult(
            threads: [makeThread(id: "a"), makeThread(id: "b")],
            filesRead: 2,
            formats: ["gemini-takeout", "chatgpt"]
        )
        XCTAssertEqual(two.summary, "2 threads from 2 files · chatgpt, gemini-takeout")
    }

    func testErrorDescriptions() {
        XCTAssertEqual(ImportError.unsupported("bad").errorDescription, "bad")
        XCTAssertEqual(ImportError.unreadable("a.json").errorDescription, "Could not read a.json.")
        XCTAssertEqual(ImportError.empty("nothing").errorDescription, "nothing")
        XCTAssertEqual(
            ImportError.noFiles.errorDescription,
            "No supported conversation export files were found."
        )
    }

    func testLocalizedDescriptionUsesErrorDescription() {
        XCTAssertEqual(
            ImportError.noFiles.localizedDescription,
            "No supported conversation export files were found."
        )
    }
}

// MARK: - Shared import helpers

final class ImportSupportTests: XCTestCase {

    func testMessageTextFromStringAndStructures() {
        XCTAssertEqual(ImportSupport.messageText(from: "  hello  "), "hello")
        XCTAssertEqual(
            ImportSupport.messageText(from: ["parts": ["a", ["text": "b"]]]),
            "a\n\nb"
        )
        XCTAssertEqual(ImportSupport.messageText(from: ["text": "x"]), "x")
        XCTAssertEqual(ImportSupport.messageText(from: ["content": ["y"]]), "y")
        XCTAssertEqual(ImportSupport.messageText(from: ["a", "b"]), "a\n\nb")
        XCTAssertEqual(ImportSupport.messageText(from: ["unrelated": 1]), "")
        XCTAssertEqual(ImportSupport.messageText(from: nil), "")
        XCTAssertEqual(ImportSupport.messageText(from: 42), "")
    }

    func testTitleFallbacks() {
        let messages = [
            ChatMessage(id: "1", role: .assistant, text: "answer"),
            ChatMessage(id: "2", role: .user, text: "How should I structure agent memory?")
        ]
        XCTAssertEqual(
            ImportSupport.title(from: messages, fallback: "  "),
            "How should I structure agent memory?"
        )
        XCTAssertEqual(
            ImportSupport.title(from: messages, fallback: "  A real title  "),
            "A real title"
        )
        XCTAssertEqual(
            ImportSupport.title(from: [], fallback: ""),
            "Untitled conversation"
        )
        let longFallback = String(repeating: "t", count: 120)
        let title = ImportSupport.title(from: [], fallback: longFallback)
        XCTAssertEqual(title.count, 91)
        XCTAssertTrue(title.hasSuffix("…"))
        let longPrompt = String(repeating: "p", count: 120)
        let promptTitle = ImportSupport.title(
            from: [ChatMessage(id: "1", role: .user, text: longPrompt)],
            fallback: ""
        )
        XCTAssertEqual(promptTitle.count, 65)
        XCTAssertTrue(promptTitle.hasSuffix("…"))
    }

    func testMessageSortingPutsUndatedLast() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let messages = [
            ChatMessage(id: "late", role: .assistant, text: "late", timestamp: start.addingTimeInterval(10)),
            ChatMessage(id: "undated", role: .user, text: "undated"),
            ChatMessage(id: "early", role: .user, text: "early", timestamp: start)
        ]
        XCTAssertEqual(
            ImportSupport.sortMessages(messages).map(\.id),
            ["early", "late", "undated"]
        )
        let undated = messages.filter { $0.timestamp == nil }
        XCTAssertEqual(ImportSupport.sortMessages(undated).map(\.id), ["undated"])
    }

    func testProviderInferenceFromFileName() {
        XCTAssertEqual(ImportSupport.providerFromFileName("chatgpt-conversations.json"), .chatgpt)
        XCTAssertEqual(ImportSupport.providerFromFileName("OpenAI Export.JSON"), .chatgpt)
        XCTAssertEqual(ImportSupport.providerFromFileName("gemini-my-activity.json"), .gemini)
        XCTAssertEqual(ImportSupport.providerFromFileName("takeout-2026.json"), .gemini)
        XCTAssertEqual(ImportSupport.providerFromFileName("bard-history.json"), .gemini)
        XCTAssertEqual(ImportSupport.providerFromFileName("claude-conversations.json"), .claude)
        XCTAssertEqual(ImportSupport.providerFromFileName("Anthropic.json"), .claude)
        XCTAssertEqual(ImportSupport.providerFromFileName("threads.json"), .other)
    }
}

// MARK: - Parser dispatch

final class ImportParserDispatchTests: XCTestCase {

    private func data(_ string: String) -> Data { Data(string.utf8) }

    func testDispatchesChatGPT() throws {
        let result = try ImportParser().parse(
            data: data(ChatGPTSamples.linear),
            fileName: "conversations.json"
        )
        XCTAssertEqual(result.formats, ["chatgpt"])
        XCTAssertEqual(result.threads.count, 1)
    }

    func testDispatchesClaude() throws {
        let result = try ImportParser().parse(
            data: data("""
            [{"uuid": "5f0f0c2e-1f47-4f8e-9a3a-1d2c3b4a5e6f", "name": "Claude chat",
              "chat_messages": [
                {"uuid": "m1", "sender": "human", "text": "Hello"},
                {"uuid": "m2", "sender": "assistant", "text": "Hi"}
              ]}]
            """),
            fileName: "conversations.json"
        )
        XCTAssertEqual(result.formats, ["claude"])
        XCTAssertEqual(result.threads.first?.provider, .claude)
    }

    func testDispatchesGeminiActivity() throws {
        let result = try ImportParser().parse(
            data: data("""
            [{"header": "Gemini Apps", "title": "Said \\"Hello\\"",
              "titleUrl": "https://gemini.google.com/app/abc", "time": "2026-01-02T10:00:00Z"}]
            """),
            fileName: "My Activity.json"
        )
        XCTAssertEqual(result.formats, ["gemini-takeout"])
        XCTAssertEqual(result.threads.first?.provider, .gemini)
    }

    func testDispatchesGenericThreadsArray() throws {
        let result = try ImportParser().parse(
            data: data("""
            {"threads": [{"id": "t1", "title": "T", "messages": [
              {"role": "user", "content": "Hi"}
            ]}]}
            """),
            fileName: "threads.json"
        )
        XCTAssertEqual(result.formats, ["generic"])
        XCTAssertEqual(result.threads.count, 1)
    }

    func testDispatchesSingleThreadObject() throws {
        let result = try ImportParser().parse(
            data: data("""
            {"id": "t1", "title": "T", "messages": [{"role": "user", "text": "Hi"}]}
            """),
            fileName: "single.json"
        )
        XCTAssertEqual(result.formats, ["generic"])
        XCTAssertEqual(result.threads.first?.id, "other:t1")
    }

    func testDispatchesHTML() throws {
        let result = try ImportParser().parse(
            data: data("""
            <html><head><title>HTML chat - Gemini</title></head><body>
            <div class="query-text">Question</div>
            <div class="model-response-text">Answer</div>
            </body></html>
            """),
            fileName: "conversation.html"
        )
        XCTAssertEqual(result.formats, ["gemini-html"])
        XCTAssertEqual(result.threads.first?.title, "HTML chat")
    }

    func testDispatchesJSONLinesWhenDocumentIsNotValidJSON() throws {
        let lines = """
        {"title": "First", "messages": [{"role": "user", "text": "one"}]}
        {"title": "Second", "messages": [{"role": "user", "text": "two"}]}
        """
        let result = try ImportParser().parse(
            data: data(lines),
            fileName: "export.jsonl"
        )
        XCTAssertEqual(result.formats, ["generic-jsonl"])
        XCTAssertEqual(result.threads.count, 2)
    }

    func testInvalidJSONIsUnsupported() {
        XCTAssertThrowsError(
            try ImportParser().parse(data: data("{nope"), fileName: "random.json")
        ) { error in
            guard case ImportError.unsupported(let message) = error else {
                return XCTFail("expected unsupported, got \(error)")
            }
            XCTAssertTrue(message.contains("not valid JSON"))
        }
    }

    func testUnrecognizedJSONIsUnsupported() {
        XCTAssertThrowsError(
            try ImportParser().parse(data: data(#"[{"foo": 1}]"#), fileName: "random.json")
        ) { error in
            guard case ImportError.unsupported(let message) = error else {
                return XCTFail("expected unsupported, got \(error)")
            }
            XCTAssertTrue(message.contains("not a recognized conversation export"))
        }
    }

    func testEmptyArrayIsUnsupported() {
        XCTAssertThrowsError(
            try ImportParser().parse(data: data("[]"), fileName: "empty.json")
        )
    }
}

// MARK: - Sample fixtures

enum ChatGPTSamples {

    static let linear = """
    [{
      "id": "5f0f0c2e-1f47-4f8e-9a3a-1d2c3b4a5e6f",
      "title": "Memory architecture",
      "create_time": 1760000000.0,
      "update_time": 1760003600.0,
      "current_node": "n2",
      "mapping": {
        "root": {"id": "root", "parent": null},
        "n1": {"id": "n1", "parent": "root", "message": {
          "id": "m1", "author": {"role": "user"}, "create_time": 1760000100.0,
          "content": {"content_type": "text", "parts": ["How should I structure memory?"]}}},
        "n2": {"id": "n2", "parent": "n1", "message": {
          "id": "m2", "author": {"role": "assistant"}, "create_time": 1760000200.0,
          "metadata": {"model_slug": "gpt-5"},
          "content": {"content_type": "text", "parts": ["Start with episodic memory."]}}}
      }
    }]
    """
}

// MARK: - ChatGPT

final class ChatGPTImporterTests: XCTestCase {

    private func data(_ string: String) -> Data { Data(string.utf8) }

    func testFollowsCurrentNodeBranch() throws {
        let json = """
        [{
          "title": "Branching", "current_node": "n2",
          "mapping": {
            "root": {"id": "root", "parent": null},
            "n1": {"id": "n1", "parent": "root", "message": {
              "id": "m1", "author": {"role": "user"}, "content": {"parts": ["question"]}}},
            "n2": {"id": "n2", "parent": "n1", "message": {
              "id": "m2", "author": {"role": "assistant"}, "content": {"parts": ["chosen answer"]}}},
            "n3": {"id": "n3", "parent": "n1", "message": {
              "id": "m3", "author": {"role": "assistant"}, "content": {"parts": ["rejected answer"]}}}
          }
        }]
        """
        let threads = try ChatGPTImporter.parse(
            json: try JSONSerialization.jsonObject(with: data(json)),
            fileName: "conversations.json"
        )
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].messages.map(\.text), ["question", "chosen answer"])
        XCTAssertFalse(threads[0].messages.contains { $0.text == "rejected answer" })
    }

    func testFallsBackToLeafWhenCurrentNodeMissing() throws {
        let json = """
        [{
          "title": "No pointer",
          "mapping": {
            "root": {"id": "root", "parent": null},
            "n1": {"id": "n1", "parent": "root", "message": {
              "id": "m1", "author": {"role": "user"}, "content": {"parts": ["first"]}}},
            "n2": {"id": "n2", "parent": "n1", "message": {
              "id": "m2", "author": {"role": "assistant"}, "content": {"parts": ["second"]}}}
          }
        }]
        """
        let threads = try ChatGPTImporter.parse(
            json: try JSONSerialization.jsonObject(with: data(json)),
            fileName: "conversations.json"
        )
        XCTAssertEqual(threads[0].messages.map(\.text), ["first", "second"])
    }

    func testSkipsHiddenAndEmptyNodesAndDerivesModel() throws {
        let json = """
        [{
          "title": "Model detection", "current_node": "n4",
          "mapping": {
            "root": {"id": "root", "parent": null},
            "n1": {"id": "n1", "parent": "root", "message": {
              "id": "m1", "author": {"role": "user"}, "metadata": {"model_slug": "gpt-5-mini"},
              "content": {"parts": ["question"]}}},
            "n2": {"id": "n2", "parent": "n1", "message": {
              "id": "m2", "author": {"role": "assistant"}, "metadata": {"model_slug": "gpt-5"},
              "content": {"parts": []}}},
            "n3": {"id": "n3", "parent": "n2", "message": {
              "id": "m3", "author": {"role": "assistant"},
              "metadata": {"is_visually_hidden_from_conversation": true},
              "content": {"parts": ["hidden"]}}},
            "n4": {"id": "n4", "parent": "n3", "message": {
              "id": "m4", "author": {"role": "assistant"}, "metadata": {"model_slug": "gpt-5"},
              "content": {"parts": ["visible"]}}}
          }
        }]
        """
        let thread = try XCTUnwrap(
            try ChatGPTImporter.parse(
                json: try JSONSerialization.jsonObject(with: data(json)),
                fileName: "conversations.json"
            ).first
        )
        XCTAssertEqual(thread.messages.map(\.text), ["question", "visible"])
        XCTAssertEqual(thread.model, "gpt-5")
        XCTAssertEqual(thread.provider, .chatgpt)
        XCTAssertEqual(thread.updatedAt, thread.createdAt)
    }

    func testTitleAndSourceURLFromUUID() throws {
        let json = """
        [{
          "id": "5f0f0c2e-1f47-4f8e-9a3a-1d2c3b4a5e6f",
          "create_time": 1760000000.0,
          "current_node": "n1",
          "mapping": {
            "n1": {"id": "n1", "parent": null, "message": {
              "id": "m1", "author": {"role": "user"}, "create_time": 1760000100.0,
              "content": {"parts": ["Generate a title from this prompt"]}}}
          }
        }]
        """
        let thread = try XCTUnwrap(
            try ChatGPTImporter.parse(
                json: try JSONSerialization.jsonObject(with: data(json)),
                fileName: "conversations.json"
            ).first
        )
        XCTAssertEqual(thread.title, "Generate a title from this prompt")
        XCTAssertEqual(
            thread.sourceURL?.absoluteString,
            "https://chatgpt.com/c/5f0f0c2e-1f47-4f8e-9a3a-1d2c3b4a5e6f"
        )
        XCTAssertEqual(thread.messages.first?.timestamp, Date(timeIntervalSince1970: 1_760_000_100))
    }

    func testEmptyAndUnsupportedInputsThrow() throws {
        XCTAssertThrowsError(
            try ChatGPTImporter.parse(
                json: try JSONSerialization.jsonObject(with: data("""
                [{"title": "Empty", "mapping": {
                  "n1": {"id": "n1", "parent": null, "message": {
                    "id": "m1", "author": {"role": "system"}, "content": {"parts": ["system only"]}}}}}]
                """)),
                fileName: "conversations.json"
            )
        ) { error in
            guard case ImportError.empty = error else { return XCTFail("\(error)") }
        }

        XCTAssertThrowsError(
            try ChatGPTImporter.parse(
                json: try JSONSerialization.jsonObject(with: data(#"{"not": "an array"}"#)),
                fileName: "conversations.json"
            )
        ) { error in
            guard case ImportError.unsupported = error else { return XCTFail("\(error)") }
        }
    }
}

// MARK: - Claude

final class ClaudeImporterTests: XCTestCase {

    private func data(_ string: String) -> Data { Data(string.utf8) }

    func testParsesMessagesKeyAndFallbacks() throws {
        let json = """
        [{
          "id": "not-a-uuid",
          "model": "claude-4",
          "created_at": "2026-02-01T09:00:00Z",
          "messages": [
            {"role": "human", "content": "Explain borrowing"},
            {"role": "assistant", "text": "Borrowing is checked at compile time.", "created_at": "2026-02-01T09:01:00Z"},
            {"role": "narrator", "text": "ignored"},
            {"role": "user", "text": "   "}
          ]
        }]
        """
        let thread = try XCTUnwrap(
            try ClaudeImporter.parse(
                json: try JSONSerialization.jsonObject(with: data(json)),
                fileName: "conversations.json"
            ).first
        )
        XCTAssertEqual(thread.provider, .claude)
        XCTAssertEqual(thread.title, "Explain borrowing")
        XCTAssertEqual(thread.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(thread.model, "claude-4")
        XCTAssertNil(thread.sourceURL)
        XCTAssertEqual(thread.id, "claude:not-a-uuid")
        XCTAssertEqual(thread.createdAt, Date(timeIntervalSince1970: 1_769_936_400))
        XCTAssertEqual(thread.updatedAt, Date(timeIntervalSince1970: 1_769_936_460))
    }

    func testSourceURLRequiresUUIDShape() throws {
        let json = """
        [{"uuid": "5f0f0c2e-1f47-4f8e-9a3a-1d2c3b4a5e6f", "name": "UUID",
          "chat_messages": [{"uuid": "m1", "sender": "human", "text": "hi"}]}]
        """
        let thread = try XCTUnwrap(
            try ClaudeImporter.parse(
                json: try JSONSerialization.jsonObject(with: data(json)),
                fileName: "conversations.json"
            ).first
        )
        XCTAssertEqual(
            thread.sourceURL?.absoluteString,
            "https://claude.ai/chat/5f0f0c2e-1f47-4f8e-9a3a-1d2c3b4a5e6f"
        )
        XCTAssertEqual(thread.deepLink, thread.sourceURL)
    }

    func testUnsupportedAndEmptyInputsThrow() throws {
        XCTAssertThrowsError(
            try ClaudeImporter.parse(
                json: try JSONSerialization.jsonObject(with: data(#"{"foo": 1}"#)),
                fileName: "conversations.json"
            )
        ) { error in
            guard case ImportError.unsupported = error else { return XCTFail("\(error)") }
        }

        XCTAssertThrowsError(
            try ClaudeImporter.parse(
                json: try JSONSerialization.jsonObject(with: data(#"[{"uuid": "x", "chat_messages": []}]"#)),
                fileName: "conversations.json"
            )
        ) { error in
            guard case ImportError.empty = error else { return XCTFail("\(error)") }
        }
    }
}

// MARK: - Gemini activity

final class GeminiActivityImporterTests: XCTestCase {

    private func data(_ string: String) -> Data { Data(string.utf8) }

    private func parse(_ json: String, fileName: String = "My Activity.json") throws -> [ConversationThread] {
        try GeminiActivityImporter.parse(
            json: try JSONSerialization.jsonObject(with: data(json)),
            fileName: fileName
        )
    }

    func testGroupsByConversationURLIgnoringQuery() throws {
        let threads = try parse("""
        [
          {"header": "Gemini Apps", "title": "Said \\"first\\"",
           "titleUrl": "https://gemini.google.com/app/abc", "time": "2026-01-02T10:00:00Z"},
          {"header": "Gemini Apps", "title": "Said \\"second\\"",
           "titleUrl": "https://gemini.google.com/app/abc?hl=en", "time": "2026-01-02T10:05:00Z"}
        ]
        """)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].messages.map(\.text), ["first", "second"])
        XCTAssertEqual(threads[0].title, "first")
        XCTAssertEqual(
            threads[0].sourceURL?.absoluteString,
            "https://gemini.google.com/app/abc"
        )
    }

    func testGroupsByDayWhenNoConversationLink() throws {
        let threads = try parse("""
        [
          {"header": "Gemini Apps", "title": "Said \\"day one\\"", "time": "2026-01-02T12:00:00Z"},
          {"header": "Gemini Apps", "title": "Said \\"day one later\\"", "time": "2026-01-02T13:00:00Z"},
          {"header": "Gemini Apps", "title": "Said \\"day two\\"", "time": "2026-01-03T12:00:00Z"}
        ]
        """)
        XCTAssertEqual(threads.count, 2)
        let dayOne = try XCTUnwrap(threads.first { $0.messages.count == 2 })
        XCTAssertEqual(dayOne.messages.map(\.text), ["day one", "day one later"])
    }

    func testDetailsAndSubtitlesExtraction() throws {
        let threads = try parse("""
        [
          {"header": "Gemini Apps", "title": "Used Gemini Apps",
           "details": [{"text": "Said \\"prompt from details\\""}],
           "time": "2026-01-02T10:00:00Z"},
          {"header": "Gemini Apps", "title": "Used Gemini Apps",
           "subtitles": [{"name": "Asked prompt from subtitle"}],
           "time": "2026-01-02T11:00:00Z"}
        ]
        """)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(
            threads[0].messages.map(\.text),
            ["prompt from details", "prompt from subtitle"]
        )
        XCTAssertEqual(threads[0].title, "prompt from details")
    }

    func testGenericTitlesAreIgnored() throws {
        let threads = try parse("""
        [{"header": "Gemini Apps", "title": "Used Gemini Apps",
          "details": [{"text": "Said \\"actual prompt\\""}],
          "time": "2026-01-02T10:00:00Z"}]
        """)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].title, "actual prompt")
    }

    func testObjectItemsFormAndNonGeminiFiltering() throws {
        let threads = try parse("""
        {"items": [
          {"header": "Gemini Apps", "title": "Said \\"gemini prompt\\"", "time": "2026-01-02T10:00:00Z"},
          {"header": "Search", "title": "Said \\"search query\\"", "time": "2026-01-02T10:00:00Z"}
        ]}
        """)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].messages.map(\.text), ["gemini prompt"])
    }

    func testGeminiFilenameAcceptsRecordsWithoutGeminiHeader() throws {
        let threads = try parse("""
        [{"title": "Said \\"still mine\\"", "time": "2026-01-02T10:00:00Z"}]
        """, fileName: "gemini-export.json")
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].messages.first?.text, "still mine")
    }

    func testUnsupportedAndEmptyInputsThrow() throws {
        XCTAssertThrowsError(try parse(#"{"foo": 1}"#)) { error in
            guard case ImportError.unsupported = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try parse("""
        [{"header": "Search", "title": "Said \\"not gemini\\"", "time": "2026-01-02T10:00:00Z"}]
        """)) { error in
            guard case ImportError.empty = error else { return XCTFail("\(error)") }
        }
    }
}

// MARK: - Gemini HTML

final class GeminiHTMLImporterTests: XCTestCase {

    func testParsesTitleBlocksRolesAndTimestamps() throws {
        let html = """
        <html><head><title>Learning kanji - Gemini</title></head><body>
        <div class="query-text" data-time="2026-01-02T10:00:00Z">How do I learn kanji?</div>
        <div class="model-response-text">2026-01-02T10:01:00Z Learn them through vocabulary.</div>
        <div class="user-query">Follow-up prompt</div>
        <div class="response-text">Follow-up answer</div>
        </body></html>
        """
        let result = try GeminiHTMLImporter.parse(html: html, fileName: "conversation.html")
        XCTAssertEqual(result.formats, ["gemini-html"])
        let thread = try XCTUnwrap(result.threads.first)
        XCTAssertEqual(thread.title, "Learning kanji")
        XCTAssertEqual(thread.messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(thread.messages.first?.text, "How do I learn kanji?")
        XCTAssertTrue(thread.messages[1].text.contains("Learn them through vocabulary."))
        XCTAssertNotNil(thread.messages.first?.timestamp)
        XCTAssertNotNil(thread.messages[1].timestamp)
        XCTAssertEqual(thread.messages[0].timestamp, Date(timeIntervalSince1970: 1_767_348_000))
    }

    func testDeduplicatesNestedBlocksWithSameText() throws {
        let html = """
        <html><head><title>Dup</title></head><body>
        <div class="conversation-container">
          <div class="query-text">Same question</div>
        </div>
        <section class="user-query"><span>Same question</span></section>
        </body></html>
        """
        let result = try GeminiHTMLImporter.parse(html: html, fileName: "conversation.html")
        XCTAssertEqual(result.threads[0].messages.map(\.text), ["Same question"])
    }

    func testRequiresRecognizableBlocks() {
        XCTAssertThrowsError(
            try GeminiHTMLImporter.parse(
                html: "<html><head><title>Nothing</title></head><body><p>plain</p></body></html>",
                fileName: "conversation.html"
            )
        ) { error in
            guard case ImportError.unsupported = error else { return XCTFail("\(error)") }
        }
    }
}

// MARK: - Generic schema

final class GenericImporterTests: XCTestCase {

    private func data(_ string: String) -> Data { Data(string.utf8) }

    private func parse(_ json: String, fileName: String = "threads.json") throws -> [ConversationThread] {
        try GenericImporter.parse(
            json: try JSONSerialization.jsonObject(with: data(json)),
            fileName: fileName
        )
    }

    func testContentShapesAndMetadata() throws {
        let threads = try parse("""
        {"threads": [{
          "id": "t1", "provider": "gemini", "name": "Solar punk transit",
          "created_at": "2026-03-01T10:00:00Z",
          "updated_at": "2026-03-01T11:00:00Z",
          "model_slug": "gemini-3",
          "url": "https://example.com/thread",
          "messages": [
            {"role": "user", "content": "How do I design this map?"},
            {"role": "assistant", "content": [{"type": "text", "text": "Start with topology."}]},
            {"role": "assistant", "parts": ["More detail"]},
            {"role": "system", "text": "system text"},
            {"role": "unknown", "text": "ignored"},
            {"role": "user", "text": "   "}
          ]
        }]}
        """)
        let thread = try XCTUnwrap(threads.first)
        XCTAssertEqual(thread.provider, .gemini)
        XCTAssertEqual(thread.title, "Solar punk transit")
        XCTAssertEqual(thread.model, "gemini-3")
        XCTAssertEqual(thread.sourceURL?.absoluteString, "https://example.com/thread")
        XCTAssertEqual(thread.messages.map(\.role), [.user, .assistant, .assistant, .system])
        XCTAssertEqual(thread.messages[1].text, "Start with topology.")
        XCTAssertEqual(thread.messages[2].text, "More detail")
        XCTAssertEqual(thread.createdAt, Date(timeIntervalSince1970: 1_772_359_200))
        XCTAssertEqual(thread.updatedAt, Date(timeIntervalSince1970: 1_772_362_800))
        XCTAssertEqual(thread.sourceFile, "threads.json")
        XCTAssertEqual(thread.id, "gemini:t1")
    }

    func testProviderInferenceFromFileNameAndFallbackDates() throws {
        let threads = try parse("""
        [{"id": "t1", "messages": [
          {"role": "user", "text": "hello", "timestamp": "2026-01-02T10:00:00Z"},
          {"role": "assistant", "text": "hi", "timestamp": "2026-01-02T10:01:00Z"}
        ]}]
        """, fileName: "claude-export.json")
        let thread = try XCTUnwrap(threads.first)
        XCTAssertEqual(thread.provider, .claude)
        XCTAssertEqual(thread.title, "hello")
        XCTAssertEqual(thread.createdAt, Date(timeIntervalSince1970: 1_767_348_000))
        XCTAssertEqual(thread.updatedAt, Date(timeIntervalSince1970: 1_767_348_060))
    }

    func testStableGeneratedIDsForRecordsWithoutID() throws {
        let json = """
        [{"title": "No id", "createdAt": "2026-01-02T10:00:00Z", "messages": [
          {"role": "user", "text": "hello"}
        ]}]
        """
        let first = try parse(json)
        let second = try parse(json)
        XCTAssertEqual(first[0].id, second[0].id)
        XCTAssertTrue(first[0].id.hasPrefix("other:"))
    }

    func testMessagesKeyIsAcceptedAsThreadContainer() throws {
        let threads = try parse("""
        {"id": "solo", "messages": [{"role": "user", "text": "just one"}]}
        """)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].id, "other:solo")
    }

    func testUnsupportedAndUnreadableRecordsThrow() throws {
        XCTAssertThrowsError(try parse(#"{"foo": 1}"#)) { error in
            guard case ImportError.unsupported = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try parse("""
        [{"id": "empty", "messages": [{"role": "user", "text": "   "}]}]
        """)) { error in
            guard case ImportError.empty = error else { return XCTFail("\(error)") }
        }
    }

    func testJSONLinesGroupedMessages() throws {
        let jsonl = """
        {"conversation_id": "c1", "message": {"role": "user", "content": "first"}}
        {"conversation_id": "c1", "message": {"role": "assistant", "content": "second"}}
        {"conversation_id": "c2", "message": {"role": "user", "content": "other"}}

        not json at all
        """
        let result = try GenericImporter.parseJSONLines(
            data: Data(jsonl.utf8),
            fileName: "export.jsonl"
        )
        XCTAssertEqual(result.formats, ["generic-jsonl"])
        XCTAssertEqual(result.threads.count, 2)
        let first = try XCTUnwrap(result.threads.first { $0.id == "other:c1" })
        XCTAssertEqual(first.messages.map(\.text), ["first", "second"])
        XCTAssertEqual(first.title, "Imported conversation")
        XCTAssertTrue(result.warnings.contains("Skipped a malformed JSONL line."))
    }

    func testJSONLinesThreadRecords() throws {
        let jsonl = """
        {"title": "First", "messages": [{"role": "user", "text": "one"}]}
        {"title": "Second", "messages": [{"role": "user", "text": "two"}]}
        """
        let result = try GenericImporter.parseJSONLines(
            data: Data(jsonl.utf8),
            fileName: "export.ndjson"
        )
        XCTAssertEqual(result.threads.map(\.title), ["First", "Second"])
    }

    func testJSONLinesWithoutReadableRecordsThrows() {
        XCTAssertThrowsError(
            try GenericImporter.parseJSONLines(
                data: Data("not json\nstill not json".utf8),
                fileName: "export.jsonl"
            )
        )
    }
}

// MARK: - ConversationImporter

final class ConversationImporterTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, _ contents: String, in folder: URL? = nil) throws -> URL {
        let base = folder ?? directory!
        let url = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testExpandFiltersRecursesAndPrioritizesExports() throws {
        let conversations = try write("chatgpt-conversations.json", "{}")
        let activity = try write("My Activity.json", "{}")
        let nested = try write("claude.json", "{}", in: directory.appendingPathComponent("nested/deep"))
        let ignored = try write("notes.txt", "hello")
        try write(".hidden.json", "{}")

        let expanded = ConversationImporter.expand([directory])
        let paths = expanded.map(\.lastPathComponent)
        XCTAssertEqual(expanded.count, 3)
        XCTAssertTrue(paths.contains(conversations.lastPathComponent))
        XCTAssertTrue(paths.contains(activity.lastPathComponent))
        XCTAssertTrue(paths.contains(nested.lastPathComponent))
        XCTAssertFalse(expanded.contains(ignored))
        XCTAssertFalse(paths.contains(".hidden.json"))
        XCTAssertTrue(
            paths.first?.contains("conversations") == true
                || paths.first?.contains("activity") == true,
            "well-known exports are read first: \(paths)"
        )
    }

    func testExpandDeduplicatesAndRejectsUnsupportedExtensions() throws {
        let file = try write("threads.json", "{}")
        let expanded = ConversationImporter.expand([file, file, try write("notes.txt", "")])
        XCTAssertEqual(expanded.count, 1)
        XCTAssertEqual(expanded.first?.lastPathComponent, "threads.json")
    }

    func testExpandStopsAtDepthFour() throws {
        let shallow = try write("shallow.json", "{}", in: directory.appendingPathComponent("a/b/c/d"))
        try write("too-deep.json", "{}", in: directory.appendingPathComponent("a/b/c/d/e"))
        let expanded = ConversationImporter.expand([directory])
        let paths = Set(expanded.map { $0.standardizedFileURL.path })
        XCTAssertTrue(paths.contains(shallow.standardizedFileURL.path))
        XCTAssertFalse(paths.contains { $0.hasSuffix("too-deep.json") })
    }

    func testImportFilesReportsFormatsAndFilesRead() throws {
        let generic = try write("threads.json", """
        {"threads": [{"id": "g1", "title": "Generic", "messages": [{"role": "user", "text": "hi"}]}]}
        """)
        let chatgpt = try write("chatgpt-conversations.json", ChatGPTSamples.linear)

        let result = try ConversationImporter.importFiles(at: [generic, chatgpt])
        XCTAssertEqual(result.filesRead, 2)
        XCTAssertEqual(result.formats, ["chatgpt", "generic"])
        XCTAssertEqual(result.threads.count, 2)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testImportFilesDeduplicatesKeepingLongerThread() throws {
        let shorter = try write("a.json", """
        {"threads": [{"id": "same", "title": "Short", "messages": [{"role": "user", "text": "one"}]}]}
        """)
        let longer = try write("b.json", """
        {"threads": [{"id": "same", "title": "Long", "messages": [
          {"role": "user", "text": "one"},
          {"role": "assistant", "text": "two"}
        ]}]}
        """)
        let result = try ConversationImporter.importFiles(at: [shorter, longer])
        XCTAssertEqual(result.threads.count, 1)
        XCTAssertEqual(result.threads[0].messages.count, 2)
    }

    func testImportFilesWarnsAboutEmptyFilesAndKeepsGoing() throws {
        let empty = try write("empty.json", "")
        let good = try write("threads.json", """
        {"threads": [{"id": "g1", "title": "Generic", "messages": [{"role": "user", "text": "hi"}]}]}
        """)
        let result = try ConversationImporter.importFiles(at: [empty, good])
        XCTAssertEqual(result.filesRead, 1)
        XCTAssertEqual(result.threads.count, 1)
        XCTAssertTrue(result.warnings.contains { $0.contains("empty.json is empty.") })
    }

    func testImportFilesThrowsWhenNothingCanBeRead() throws {
        let empty = try write("empty.json", "")
        XCTAssertThrowsError(try ConversationImporter.importFiles(at: [empty])) { error in
            XCTAssertEqual(error.localizedDescription, "No conversations could be imported.")
        }

        let unsupported = try write("random.json", #"{"foo": "bar"}"#)
        XCTAssertThrowsError(try ConversationImporter.importFiles(at: [unsupported])) { error in
            guard case ImportError.unsupported = error else { return XCTFail("\(error)") }
        }
    }

    func testImportFilesThrowsWhenNoSupportedFilesExist() throws {
        let text = try write("notes.txt", "hello")
        XCTAssertThrowsError(try ConversationImporter.importFiles(at: [text])) { error in
            guard case ImportError.noFiles = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try ConversationImporter.importFiles(at: [])) { error in
            guard case ImportError.noFiles = error else { return XCTFail("\(error)") }
        }
    }

    func testImportFilesReadsJSONLines() throws {
        let url = try write("export.jsonl", """
        {"title": "Line one", "messages": [{"role": "user", "text": "hello"}]}
        {"title": "Line two", "messages": [{"role": "user", "text": "again"}]}
        """)
        let result = try ConversationImporter.importFiles(at: [url])
        XCTAssertEqual(result.formats, ["generic-jsonl"])
        XCTAssertEqual(result.threads.count, 2)
    }
}
