import XCTest
@testable import MindMapCore

final class ImportTests: XCTestCase {

    func testChatGPTParsingThroughParser() throws {
        let json = """
        [{
          "title": "Memory architecture for an agent",
          "create_time": 1760000000.0,
          "update_time": 1760003600.0,
          "current_node": "n2",
          "mapping": {
            "root": {"id": "root", "parent": null},
            "n1": {
              "id": "n1", "parent": "root",
              "message": {
                "id": "m1", "author": {"role": "user"}, "create_time": 1760000100.0,
                "content": {"content_type": "text", "parts": ["How should I structure agent memory?"]}
              }
            },
            "n2": {
              "id": "n2", "parent": "n1",
              "message": {
                "id": "m2", "author": {"role": "assistant"}, "create_time": 1760000200.0,
                "metadata": {"model_slug": "gpt-5"},
                "content": {"content_type": "text", "parts": ["Start with episodic and semantic memory."]}
              }
            },
            "n3": {
              "id": "n3", "parent": "n2",
              "message": {
                "id": "m3", "author": {"role": "assistant"}, "create_time": 1760000300.0,
                "metadata": {"is_visually_hidden_from_conversation": true},
                "content": {"content_type": "text", "parts": ["hidden"]}
              }
            }
          }
        }]
        """.data(using: .utf8)!

        let result = try ImportParser().parse(data: json, fileName: "conversations.json")
        XCTAssertEqual(result.threads.count, 1)
        let thread = try XCTUnwrap(result.threads.first)
        XCTAssertEqual(thread.provider, .chatgpt)
        XCTAssertEqual(thread.messages.count, 2, "hidden nodes are skipped")
        XCTAssertEqual(thread.title, "Memory architecture for an agent")
        XCTAssertEqual(thread.model, "gpt-5")
        XCTAssertEqual(thread.messages.first?.role, .user)
        XCTAssertTrue(thread.messages.last?.text.contains("episodic") == true)
    }

    func testGeminiActivityParsingGroupsByConversationURL() throws {
        let json = """
        [
          {"header": "Gemini Apps", "title": "Said \\"How do I learn kanji faster?\\"",
           "titleUrl": "https://gemini.google.com/app/abc123", "time": "2026-01-02T10:00:00.000Z",
           "products": ["Gemini Apps"]},
          {"header": "Gemini Apps", "title": "Said \\"What about radicals?\\"",
           "titleUrl": "https://gemini.google.com/app/abc123?hl=en", "time": "2026-01-02T10:05:00.000Z",
           "products": ["Gemini Apps"]},
          {"header": "Gemini Apps", "title": "Said \\"Best pizza in Naples?\\"",
           "time": "2026-01-03T18:00:00.000Z", "products": ["Gemini Apps"]}
        ]
        """.data(using: .utf8)!

        let result = try ImportParser().parse(data: json, fileName: "My Activity.json")
        XCTAssertEqual(result.threads.count, 2)
        let kanji = try XCTUnwrap(result.threads.first { $0.title.contains("kanji") })
        XCTAssertEqual(kanji.provider, .gemini)
        XCTAssertEqual(kanji.messages.count, 2)
        XCTAssertEqual(kanji.sourceURL?.absoluteString, "https://gemini.google.com/app/abc123")
        XCTAssertEqual(kanji.messages.first?.text, "How do I learn kanji faster?")
    }

    func testClaudeParsing() throws {
        let json = """
        [{
          "uuid": "5f0f0c2e-1f47-4f8e-9a3a-1d2c3b4a5e6f",
          "name": "Rust ownership",
          "created_at": "2026-02-01T09:00:00Z",
          "updated_at": "2026-02-01T10:00:00Z",
          "chat_messages": [
            {"uuid": "m1", "sender": "human", "text": "Explain borrowing", "created_at": "2026-02-01T09:00:00Z"},
            {"uuid": "m2", "sender": "assistant", "text": "Borrowing is checked at compile time.", "created_at": "2026-02-01T09:01:00Z"}
          ]
        }]
        """.data(using: .utf8)!

        let result = try ImportParser().parse(data: json, fileName: "conversations.json")
        XCTAssertEqual(result.threads.count, 1)
        let thread = try XCTUnwrap(result.threads.first)
        XCTAssertEqual(thread.provider, .claude)
        XCTAssertEqual(thread.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(thread.deepLink?.absoluteString, "https://claude.ai/chat/5f0f0c2e-1f47-4f8e-9a3a-1d2c3b4a5e6f")
    }

    func testGenericSchemaAndArray() throws {
        let json = """
        {"threads": [
          {"id": "t1", "provider": "gemini", "title": "Solar punk transit",
           "createdAt": "2026-03-01T10:00:00Z",
           "messages": [
             {"role": "user", "content": "How do I design this map?"},
             {"role": "assistant", "content": [{"type": "text", "text": "Start with topology."}]}
           ]}
        ]}
        """.data(using: .utf8)!

        let result = try ImportParser().parse(data: json, fileName: "threads.json")
        XCTAssertEqual(result.threads.count, 1)
        XCTAssertEqual(result.threads[0].provider, .gemini)
        XCTAssertEqual(result.threads[0].messages.count, 2)
        XCTAssertEqual(result.threads[0].messages[1].text, "Start with topology.")
    }

    func testSampleExportsOnDisk() throws {
        let samples = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Samples", isDirectory: true)

        let files = [
            "chatgpt-conversations.json",
            "gemini-my-activity.json",
            "claude-conversations.json",
            "generic-threads.json",
            "opencode-sample.db"
        ].map { samples.appendingPathComponent($0) }

        for file in files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.lastPathComponent)
            let result = try ConversationImporter.importFiles(at: [file])
            XCTAssertGreaterThan(result.threads.count, 0, file.lastPathComponent)
        }

        // Dragging a folder walks into it.
        let folderResult = try ConversationImporter.importFiles(at: [samples])
        XCTAssertGreaterThanOrEqual(folderResult.threads.count, 8)
        XCTAssertEqual(folderResult.filesRead, 5)
    }

    func testOpenCodeSQLiteImport() throws {
        let samples = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Samples", isDirectory: true)
        let database = samples.appendingPathComponent("opencode-sample.db")

        let result = try ConversationImporter.importFiles(at: [database])
        XCTAssertEqual(result.threads.count, 2)
        XCTAssertTrue(result.threads.allSatisfy { $0.provider == .opencode })

        let main = try XCTUnwrap(result.threads.first { $0.title.contains("smoke test") })
        XCTAssertEqual(main.messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(main.model, "deepseek-v4.1-flash")
        XCTAssertEqual(main.totalCost, 0.42, accuracy: 0.0001)
        XCTAssertEqual(main.tokenCount, 23_400)
        XCTAssertEqual(main.messages.compactMap(\.cost).count, 2)
        XCTAssertEqual(main.messages.first { $0.role == .assistant }?.cost ?? 0, 0.21, accuracy: 0.0001)
        XCTAssertTrue(main.messages.contains { $0.text.contains("local SQLite session store") })
        XCTAssertFalse(main.messages.contains { $0.text.contains("SECRET REASONING") })
        XCTAssertFalse(result.threads.contains { $0.title.contains("Subagent") })
        XCTAssertFalse(result.threads.contains { $0.title == "Empty session" })

        let fallback = try XCTUnwrap(result.threads.first { $0.title.contains("Fallback title") })
        XCTAssertEqual(fallback.messages.count, 2)

        let limited = try OpenCodeImporter.parse(databaseURL: database, sessionLimit: 1)
        XCTAssertEqual(limited.threads.count, 1)
        XCTAssertTrue(limited.threads[0].title.contains("smoke test"))
    }

    func testUnsupportedFile() throws {
        let json = #"{"foo": "bar"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try ImportParser().parse(data: json, fileName: "random.json"))
    }

    func testHTMLFallback() throws {
        let html = """
        <html><head><title>Learning kanji - Gemini</title></head><body>
        <div class="conversation-container">
          <div class="query-text">How do I learn kanji efficiently?</div>
          <div class="model-response-text">Learn them through vocabulary you care about.</div>
        </div>
        </body></html>
        """
        let result = try ImportParser().parse(data: html.data(using: .utf8)!, fileName: "conversation.html")
        XCTAssertEqual(result.threads.count, 1)
        XCTAssertEqual(result.threads[0].messages.count, 2)
        XCTAssertEqual(result.threads[0].title, "Learning kanji")
        XCTAssertEqual(result.threads[0].messages[0].role, .user)
    }
}
