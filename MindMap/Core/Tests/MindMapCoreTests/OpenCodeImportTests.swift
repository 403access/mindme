import XCTest
import SQLite3
@testable import MindMapCore

// MARK: - Test database helpers

private final class TestDatabase {
    let url: URL
    private var handle: OpaquePointer?

    init(url: URL, schema: String) throws {
        self.url = url
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard result == SQLITE_OK else {
            throw NSError(domain: "TestDatabase", code: Int(result))
        }
        try exec(schema)
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        guard result == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw NSError(
                domain: "TestDatabase",
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    func insertSession(
        id: String,
        title: String?,
        created: Int64,
        updated: Int64,
        model: String? = nil,
        cost: Double? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        parentID: String? = nil,
        archived: Int64? = nil,
        includeCostColumns: Bool = true
    ) throws {
        let columns: String
        let values: String
        if includeCostColumns {
            columns = "(id, project_id, parent_id, title, time_created, time_updated, time_archived, model, cost, tokens_input, tokens_output, tokens_cache_read)"
            values = [
                quote(id),
                "NULL",
                parentID.map(quote) ?? "NULL",
                title.map(quote) ?? "NULL",
                String(created),
                String(updated),
                archived.map(String.init) ?? "NULL",
                model.map(quote) ?? "NULL",
                String(cost ?? 0),
                String(inputTokens),
                String(outputTokens),
                String(cachedTokens)
            ].joined(separator: ", ")
        } else {
            columns = "(id, project_id, parent_id, title, time_created, time_updated, time_archived, model)"
            values = [
                quote(id),
                "NULL",
                parentID.map(quote) ?? "NULL",
                title.map(quote) ?? "NULL",
                String(created),
                String(updated),
                archived.map(String.init) ?? "NULL",
                model.map(quote) ?? "NULL"
            ].joined(separator: ", ")
        }
        try exec("INSERT INTO session_v2 \(columns) VALUES (\(values));")
    }

    func insertMessage(
        id: String,
        sessionID: String,
        type: String,
        seq: Int,
        data: [String: Any]
    ) throws {
        let json = (try? JSONSerialization.data(withJSONObject: data))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        try exec("""
        INSERT INTO session_message (id, session_id, type, seq, time_created, time_updated, data)
        VALUES (\(quote(id)), \(quote(sessionID)), \(quote(type)), \(seq), 0, 0, \(quote(json)));
        """)
    }
}

private enum Schema {
    static let full = """
    CREATE TABLE session_v2 (
      id text PRIMARY KEY,
      project_id text,
      parent_id text,
      title text,
      time_created integer,
      time_updated integer,
      time_archived integer,
      model text,
      cost real DEFAULT 0 NOT NULL,
      tokens_input integer DEFAULT 0 NOT NULL,
      tokens_output integer DEFAULT 0 NOT NULL,
      tokens_cache_read integer DEFAULT 0 NOT NULL
    );
    CREATE TABLE session_message (
      id text PRIMARY KEY,
      session_id text,
      type text,
      seq integer,
      time_created integer,
      time_updated integer,
      data text
    );
    """

    static let legacy = """
    CREATE TABLE session_v2 (
      id text PRIMARY KEY,
      project_id text,
      parent_id text,
      title text,
      time_created integer,
      time_updated integer,
      time_archived integer,
      model text
    );
    CREATE TABLE session_message (
      id text PRIMARY KEY,
      session_id text,
      type text,
      seq integer,
      time_created integer,
      time_updated integer,
      data text
    );
    """
}

// MARK: - OpenCode importer

final class OpenCodeImporterTests: XCTestCase {

    private var directory: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapOpenCode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        databaseURL = directory.appendingPathComponent("opencode.db")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeDatabase(schema: String = Schema.full) throws -> TestDatabase {
        try TestDatabase(url: databaseURL, schema: schema)
    }

    func testConstantsDocumentedDefaults() {
        XCTAssertEqual(OpenCodeImporter.defaultSessionLimit, 150)
        XCTAssertEqual(OpenCodeImporter.firstMessagesPerThread, 10)
        XCTAssertEqual(OpenCodeImporter.lastMessagesPerThread, 50)
        XCTAssertEqual(OpenCodeImporter.messageCharacterLimit, 5_000)
    }

    func testFullSchemaMapsCostTokensAndMessageContent() throws {
        let database = try makeDatabase()
        try database.insertSession(
            id: "ses_1",
            title: "Costly session",
            created: 1_793_000_000_000,
            updated: 1_793_003_000_000,
            model: #"{"id":"deepseek-v4.1-flash","providerID":"opencode-go"}"#,
            cost: 1.25,
            inputTokens: 100,
            outputTokens: 50,
            cachedTokens: 25
        )
        try database.insertMessage(
            id: "m1",
            sessionID: "ses_1",
            type: "user",
            seq: 1,
            data: ["text": "hello", "time": ["created": 1_793_000_001_000]]
        )
        try database.insertMessage(
            id: "m2",
            sessionID: "ses_1",
            type: "assistant",
            seq: 2,
            data: [
                "content": [
                    ["type": "reasoning", "text": "SECRET REASONING SHOULD NOT BE IMPORTED"],
                    ["type": "text", "text": "world"]
                ],
                "time": ["created": 1_793_000_002_000],
                "cost": 0.5,
                "tokens": [
                    "input": 10,
                    "output": 20,
                    "cache": ["read": 3, "write": 2]
                ]
            ]
        )
        try database.insertMessage(
            id: "m3",
            sessionID: "ses_1",
            type: "system",
            seq: 3,
            data: ["text": "system context"]
        )
        try database.insertMessage(
            id: "m4",
            sessionID: "ses_1",
            type: "assistant",
            seq: 4,
            data: ["content": "plain string answer"]
        )

        let result = try OpenCodeImporter.parse(databaseURL: databaseURL)
        XCTAssertEqual(result.filesRead, 1)
        XCTAssertEqual(result.formats, ["opencode"])
        XCTAssertEqual(result.threads.count, 1)

        let thread = try XCTUnwrap(result.threads.first)
        XCTAssertEqual(thread.id, "opencode:ses_1")
        XCTAssertEqual(thread.provider, .opencode)
        XCTAssertEqual(thread.title, "Costly session")
        XCTAssertEqual(thread.model, "deepseek-v4.1-flash")
        XCTAssertEqual(thread.sourceFile, "opencode.db")
        XCTAssertNil(thread.sourceURL)
        XCTAssertEqual(thread.messages.map(\.role), [.user, .assistant, .assistant])
        XCTAssertEqual(thread.messages.map(\.text), ["hello", "world", "plain string answer"])
        XCTAssertNil(thread.messages[0].cost)
        XCTAssertEqual(thread.messages[1].cost ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(thread.messages[1].inputTokens, 10)
        XCTAssertEqual(thread.messages[1].outputTokens, 20)
        XCTAssertEqual(thread.messages[1].cachedTokens, 5)
        XCTAssertEqual(thread.messages[1].timestamp, Date(timeIntervalSince1970: 1_793_000_002))
        XCTAssertEqual(thread.cost ?? 0, 1.25, accuracy: 0.0001)
        XCTAssertEqual(thread.tokenCount, 175)
        XCTAssertEqual(thread.createdAt, Date(timeIntervalSince1970: 1_793_000_000))
        XCTAssertEqual(thread.updatedAt, Date(timeIntervalSince1970: 1_793_003_000))
        XCTAssertFalse(thread.messages.contains { $0.text.contains("SECRET REASONING") })
    }

    func testLegacySchemaWithoutCostColumnsStillImports() throws {
        let database = try makeDatabase(schema: Schema.legacy)
        try database.insertSession(
            id: "ses_legacy",
            title: "Legacy",
            created: 1_793_000_000_000,
            updated: 1_793_000_100_000,
            includeCostColumns: false
        )
        try database.insertMessage(
            id: "m1",
            sessionID: "ses_legacy",
            type: "user",
            seq: 1,
            data: ["text": "legacy prompt"]
        )
        try database.insertMessage(
            id: "m2",
            sessionID: "ses_legacy",
            type: "assistant",
            seq: 2,
            data: [
                "content": [["type": "text", "text": "legacy answer"]],
                "tokens": ["input": 7, "output": 8, "cache": ["read": 1]]
            ]
        )

        let result = try OpenCodeImporter.parse(databaseURL: databaseURL)
        let thread = try XCTUnwrap(result.threads.first)
        XCTAssertNil(thread.cost)
        XCTAssertNil(thread.inputTokens)
        XCTAssertEqual(thread.messages.count, 2)
        XCTAssertEqual(thread.tokenCount, 16, "falls back to the per-message token counts")
        XCTAssertEqual(thread.messages[1].cachedTokens, 1)
    }

    func testSkipsSubagentArchivedAndEmptySessions() throws {
        let database = try makeDatabase()
        try database.insertSession(
            id: "ses_top",
            title: "Top level",
            created: 1_793_000_000_000,
            updated: 1_793_000_300_000
        )
        try database.insertSession(
            id: "ses_sub",
            title: "Subagent should not import",
            created: 1_793_000_100_000,
            updated: 1_793_000_200_000,
            parentID: "ses_top"
        )
        try database.insertSession(
            id: "ses_archived",
            title: "Archived should not import",
            created: 1_793_000_100_000,
            updated: 1_793_000_250_000,
            archived: 1_793_000_260_000
        )
        try database.insertSession(
            id: "ses_empty",
            title: "Empty",
            created: 1_793_000_000_000,
            updated: 1_793_000_100_000
        )
        for (id, session) in [("m1", "ses_top"), ("m2", "ses_sub"), ("m3", "ses_archived")] {
            try database.insertMessage(
                id: "\(id)-user",
                sessionID: session,
                type: "user",
                seq: 1,
                data: ["text": "prompt in \(session)"]
            )
        }

        let result = try OpenCodeImporter.parse(databaseURL: databaseURL)
        XCTAssertEqual(result.threads.map(\.id), ["opencode:ses_top"])
        XCTAssertEqual(result.threads.first?.messages.map(\.text), ["prompt in ses_top"])
    }

    func testSessionLimitUsesMostRecentlyUpdatedFirst() throws {
        let database = try makeDatabase()
        try database.insertSession(
            id: "ses_old",
            title: "Old",
            created: 1_793_000_000_000,
            updated: 1_793_000_100_000
        )
        try database.insertSession(
            id: "ses_new",
            title: "New",
            created: 1_793_000_000_000,
            updated: 1_793_000_900_000
        )
        try database.insertMessage(
            id: "m-old",
            sessionID: "ses_old",
            type: "user",
            seq: 1,
            data: ["text": "old prompt"]
        )
        try database.insertMessage(
            id: "m-new",
            sessionID: "ses_new",
            type: "user",
            seq: 1,
            data: ["text": "new prompt"]
        )

        let all = try OpenCodeImporter.parse(databaseURL: databaseURL)
        XCTAssertEqual(all.threads.map(\.id), ["opencode:ses_new", "opencode:ses_old"])

        let limited = try OpenCodeImporter.parse(databaseURL: databaseURL, sessionLimit: 1)
        XCTAssertEqual(limited.threads.map(\.id), ["opencode:ses_new"])
    }

    func testLongSessionsKeepFirstTenAndLastFiftyMessages() throws {
        let database = try makeDatabase()
        try database.insertSession(
            id: "ses_long",
            title: "Long",
            created: 1_793_000_000_000,
            updated: 1_793_000_900_000
        )
        for seq in 1...70 {
            let type = seq % 2 == 1 ? "user" : "assistant"
            let data: [String: Any] = type == "user"
                ? ["text": "message \(seq)"]
                : ["content": [["type": "text", "text": "message \(seq)"]]]
            try database.insertMessage(
                id: "m\(seq)",
                sessionID: "ses_long",
                type: type,
                seq: seq,
                data: data
            )
        }

        let thread = try XCTUnwrap(
            try OpenCodeImporter.parse(databaseURL: databaseURL).threads.first
        )
        XCTAssertEqual(thread.messages.count, 60)
        XCTAssertEqual(thread.messages.first?.text, "message 1")
        XCTAssertEqual(thread.messages.last?.text, "message 70")
        XCTAssertEqual(thread.messages.map(\.text), (1...10).map { "message \($0)" } + (21...70).map { "message \($0)" })
    }

    func testLongMessagesAreTruncated() throws {
        let database = try makeDatabase()
        try database.insertSession(
            id: "ses_long_message",
            title: "Long message",
            created: 1_793_000_000_000,
            updated: 1_793_000_100_000
        )
        let text = String(repeating: "a", count: 6_000)
        try database.insertMessage(
            id: "m1",
            sessionID: "ses_long_message",
            type: "user",
            seq: 1,
            data: ["text": text]
        )

        let message = try XCTUnwrap(
            try OpenCodeImporter.parse(databaseURL: databaseURL).threads.first?.messages.first
        )
        XCTAssertEqual(message.text.count, OpenCodeImporter.messageCharacterLimit + 1)
        XCTAssertTrue(message.text.hasSuffix("…"))
    }

    func testFallbackTitleAndModelLabelShapes() throws {
        let database = try makeDatabase()
        try database.insertSession(
            id: "ses_untitled",
            title: nil,
            created: 1_793_000_000_000,
            updated: 1_793_000_100_000,
            model: String(repeating: "m", count: 100)
        )
        try database.insertMessage(
            id: "m1",
            sessionID: "ses_untitled",
            type: "user",
            seq: 1,
            data: ["text": "  A fallback title from the prompt  "]
        )
        try database.insertSession(
            id: "ses_plain_model",
            title: "Plain model",
            created: 1_793_000_000_000,
            updated: 1_793_000_200_000,
            model: "plain-model"
        )
        try database.insertMessage(
            id: "m2",
            sessionID: "ses_plain_model",
            type: "user",
            seq: 1,
            data: ["text": "plain"]
        )

        let threads = try OpenCodeImporter.parse(databaseURL: databaseURL).threads
        let untitled = try XCTUnwrap(threads.first { $0.id == "opencode:ses_untitled" })
        XCTAssertEqual(untitled.title, "A fallback title from the prompt")
        XCTAssertNil(untitled.model, "an overlong model label is discarded")

        let plain = try XCTUnwrap(threads.first { $0.id == "opencode:ses_plain_model" })
        XCTAssertEqual(plain.model, "plain-model")
    }

    func testMissingDatabaseAndBadSchemaThrow() throws {
        let missing = directory.appendingPathComponent("missing.db")
        XCTAssertThrowsError(try OpenCodeImporter.parse(databaseURL: missing)) { error in
            guard case ImportError.unreadable = error else { return XCTFail("\(error)") }
        }

        let noSessions = try makeDatabase(schema: """
        CREATE TABLE session_message (id text, session_id text, type text, seq integer, data text);
        """)
        _ = noSessions
        XCTAssertThrowsError(try OpenCodeImporter.parse(databaseURL: databaseURL)) { error in
            guard case ImportError.unsupported(let message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("session_v2"))
        }

        let noMessages = try makeDatabase(schema: """
        CREATE TABLE session_v2 (
          id text PRIMARY KEY, project_id text, parent_id text, title text,
          time_created integer, time_updated integer, time_archived integer, model text
        );
        """)
        _ = noMessages
        try noMessages.insertSession(
            id: "ses_no_messages",
            title: "No messages",
            created: 1_793_000_000_000,
            updated: 1_793_000_100_000,
            includeCostColumns: false
        )
        XCTAssertThrowsError(try OpenCodeImporter.parse(databaseURL: databaseURL)) { error in
            guard case ImportError.empty = error else { return XCTFail("\(error)") }
            XCTAssertTrue(error.localizedDescription.contains("subagent"))
        }
    }

    func testNotADatabaseFileThrows() throws {
        try Data("this is not sqlite".utf8).write(to: databaseURL)
        XCTAssertThrowsError(try OpenCodeImporter.parse(databaseURL: databaseURL))
    }

    func testIsSQLiteDatabaseDetectsHeader() throws {
        let sample = samplesDirectory.appendingPathComponent("opencode-sample.db")
        XCTAssertTrue(OpenCodeImporter.isSQLiteDatabase(at: sample))

        let json = directory.appendingPathComponent("file.json")
        try Data("{}".utf8).write(to: json)
        XCTAssertFalse(OpenCodeImporter.isSQLiteDatabase(at: json))

        XCTAssertFalse(OpenCodeImporter.isSQLiteDatabase(at: directory.appendingPathComponent("nope.db")))
    }

    func testSampleDatabaseThroughConversationImporter() throws {
        let sample = samplesDirectory.appendingPathComponent("opencode-sample.db")
        let result = try ConversationImporter.importFiles(at: [sample])
        XCTAssertEqual(result.formats, ["opencode"])
        XCTAssertEqual(result.threads.count, 2)
    }

    private var samplesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Samples", isDirectory: true)
    }
}
