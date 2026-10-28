import Foundation
import SQLite3

/// Imports conversations from OpenCode's local SQLite store.
///
/// OpenCode keeps top-level sessions in `session_v2` and their messages in
/// `session_message`. Only human prompts and assistant text are imported — tool
/// calls, patches, reasoning and snapshots stay out of the map. Subagent
/// sessions (`parent_id` != NULL) are skipped, and only the most recent
/// sessions are read so a long-running coding archive stays usable.
public enum OpenCodeImporter {

    public static let defaultSessionLimit = 150
    public static let firstMessagesPerThread = 10
    public static let lastMessagesPerThread = 50
    public static let messageCharacterLimit = 5_000

    /// Conventional OpenCode data locations, newest first.
    public static func defaultDatabaseURL() -> URL? {
        var candidates: [URL] = []
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            candidates.append(
                URL(fileURLWithPath: xdg, isDirectory: true)
                    .appendingPathComponent("opencode/opencode.db")
            )
        }
        candidates.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/opencode/opencode.db")
        )
        if let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            candidates.append(applicationSupport.appendingPathComponent("opencode/opencode.db"))
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func parse(
        databaseURL: URL,
        sessionLimit: Int = defaultSessionLimit
    ) throws -> ImportResult {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw ImportError.unreadable(databaseURL.lastPathComponent)
        }
        let database = try OpenCodeDatabase(url: databaseURL)
        let sessions = try database.sessions(limit: max(1, sessionLimit))

        var threads: [ConversationThread] = []
        for session in sessions {
            if let thread = try database.thread(for: session, sourceName: databaseURL.lastPathComponent) {
                threads.append(thread)
            }
        }

        guard !threads.isEmpty else {
            throw ImportError.empty(
                "No readable OpenCode conversations were found. OpenCode subagent sessions are skipped."
            )
        }
        return ImportResult(threads: threads, filesRead: 1, formats: ["opencode"])
    }

    /// Cheap check used before reading a file into memory.
    public static func isSQLiteDatabase(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 16)
        return header.starts(with: Data("SQLite format 3\u{0}".utf8))
    }
}

// MARK: - SQLite

private let openCodeTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct OpenCodeSessionRow {
    var id: String
    var title: String?
    var createdAt: Date
    var updatedAt: Date
    var model: String?
}

private struct OpenCodeMessageDraft {
    var seq: Int64
    var id: String
    var role: MessageRole
    var text: String
    var timestamp: Date?
}

private final class OpenCodeDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(url.path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw ImportError.unsupported("Could not open the OpenCode database: \(message)")
        }
        self.handle = database
        sqlite3_busy_timeout(database, 4_000)
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func sessions(limit: Int) throws -> [OpenCodeSessionRow] {
        guard let handle else { throw ImportError.unsupported("OpenCode database is closed.") }
        guard try hasTable("session_v2", in: handle) else {
            throw ImportError.unsupported(
                "This SQLite file does not contain an OpenCode session_v2 table. OpenCode may need to be updated once before its sessions can be imported."
            )
        }

        let statement = try SQLiteStatement(
            database: handle,
            sql: """
            SELECT id, title, time_created, time_updated, model
            FROM session_v2
            WHERE parent_id IS NULL AND time_archived IS NULL
            ORDER BY time_updated DESC
            LIMIT ?
            """
        )
        statement.bind(limit, at: 1)

        var rows: [OpenCodeSessionRow] = []
        while try statement.step() {
            guard let id = statement.text(0) else { continue }
            let created = FlexibleDate.fromTimestamp(statement.double(2))
                ?? Date(timeIntervalSince1970: 0)
            let updated = FlexibleDate.fromTimestamp(statement.double(3)) ?? created
            rows.append(OpenCodeSessionRow(
                id: id,
                title: statement.text(1)?.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: created,
                updatedAt: updated,
                model: Self.modelLabel(statement.text(4))
            ))
        }
        return rows
    }

    func thread(for session: OpenCodeSessionRow, sourceName: String) throws -> ConversationThread? {
        guard let handle else { return nil }
        let tableExists = try hasTable("session_message", in: handle)
        guard tableExists else { return nil }

        let first = try SQLiteStatement(
            database: handle,
            sql: """
            SELECT id, type, data, seq FROM session_message
            WHERE session_id = ? AND type IN ('user', 'assistant')
            ORDER BY seq ASC LIMIT ?
            """
        )
        let last = try SQLiteStatement(
            database: handle,
            sql: """
            SELECT id, type, data, seq FROM session_message
            WHERE session_id = ? AND type IN ('user', 'assistant')
            ORDER BY seq DESC LIMIT ?
            """
        )
        first.bind(session.id, at: 1)
        first.bind(OpenCodeImporter.firstMessagesPerThread, at: 2)
        last.bind(session.id, at: 1)
        last.bind(OpenCodeImporter.lastMessagesPerThread, at: 2)

        var drafts: [Int64: OpenCodeMessageDraft] = [:]
        try collect(from: first, into: &drafts)
        try collect(from: last, into: &drafts)

        let ordered = drafts.values.sorted { $0.seq < $1.seq }
        guard !ordered.isEmpty else { return nil }

        let messages = ordered.map {
            ChatMessage(
                id: "opencode:\($0.id)",
                role: $0.role,
                text: $0.text,
                timestamp: $0.timestamp
            )
        }

        let fallbackTitle = messages.first(where: { $0.role == .user })?.text
            ?? messages.first?.text
            ?? "OpenCode session"
        let rawTitle = session.title?.isEmpty == false ? session.title! : fallbackTitle
        let title = TextTools.truncated(rawTitle, limit: 90)

        let firstTimestamp = messages.compactMap(\.timestamp).min()
        let lastTimestamp = messages.compactMap(\.timestamp).max()
        let createdAt = min(session.createdAt, firstTimestamp ?? session.createdAt)
        let updatedAt = max(session.updatedAt, lastTimestamp ?? session.updatedAt)

        return ConversationThread(
            id: "opencode:\(session.id)",
            provider: .opencode,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messages: messages,
            model: session.model,
            sourceURL: nil,
            sourceFile: sourceName
        )
    }

    // MARK: - Parsing

    private func collect(
        from statement: SQLiteStatement,
        into drafts: inout [Int64: OpenCodeMessageDraft]
    ) throws {
        while try statement.step() {
            guard let id = statement.text(0),
                  let type = statement.text(1),
                  let raw = statement.text(2),
                  let data = raw.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }

            let seq = statement.int64(3)
            if drafts[seq] != nil { continue }

            let role: MessageRole = type == "user" ? .user : .assistant
            var text: String
            if role == .user {
                text = (object["text"] as? String) ?? ""
            } else {
                text = Self.assistantText(object)
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if text.count > OpenCodeImporter.messageCharacterLimit {
                text = String(text.prefix(OpenCodeImporter.messageCharacterLimit))
                    .trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            }

            let timeObject = object["time"] as? [String: Any]
            let timestamp = FlexibleDate.parse(timeObject?["created"])

            drafts[seq] = OpenCodeMessageDraft(
                seq: seq,
                id: id,
                role: role,
                text: text,
                timestamp: timestamp
            )
        }
    }

    private static func assistantText(_ object: [String: Any]) -> String {
        guard let content = object["content"] else { return "" }
        if let string = content as? String { return string }
        guard let parts = content as? [[String: Any]] else { return "" }
        var pieces: [String] = []
        for part in parts {
            guard (part["type"] as? String) == "text" else { continue }
            if let text = part["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { pieces.append(trimmed) }
            }
        }
        return pieces.joined(separator: "\n\n")
    }

    private static func modelLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if let data = raw.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let id = object["id"] as? String, !id.isEmpty {
            return id
        }
        return raw.count <= 72 ? raw : nil
    }

    private func hasTable(_ name: String, in database: OpaquePointer) throws -> Bool {
        let statement = try SQLiteStatement(
            database: database,
            sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
        )
        statement.bind(name, at: 1)
        return try statement.step()
    }
}

private final class SQLiteStatement {
    private let database: OpaquePointer
    private let handle: OpaquePointer

    init(database: OpaquePointer, sql: String) throws {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw ImportError.unsupported(
                "OpenCode database query failed: \(String(cString: sqlite3_errmsg(database)))"
            )
        }
        self.database = database
        self.handle = statement
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func bind(_ string: String, at index: Int32) {
        sqlite3_bind_text(handle, index, string, -1, openCodeTransient)
    }

    func bind(_ int: Int, at index: Int32) {
        sqlite3_bind_int64(handle, index, Int64(int))
    }

    func step() throws -> Bool {
        let result = sqlite3_step(handle)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw ImportError.unsupported(
            "OpenCode database query failed: \(String(cString: sqlite3_errmsg(database)))"
        )
    }

    func text(_ index: Int32) -> String? {
        guard let value = sqlite3_column_text(handle, index) else { return nil }
        return String(cString: value)
    }

    func int64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(handle, index)
    }

    func double(_ index: Int32) -> Double {
        sqlite3_column_double(handle, index)
    }
}
