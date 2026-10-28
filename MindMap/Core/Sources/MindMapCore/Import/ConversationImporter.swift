import Foundation

public struct ImportResult: Sendable {
    public var threads: [ConversationThread]
    public var warnings: [String]
    public var filesRead: Int
    public var formats: Set<String>

    public init(threads: [ConversationThread] = [], warnings: [String] = [], filesRead: Int = 0, formats: Set<String> = []) {
        self.threads = threads
        self.warnings = warnings
        self.filesRead = filesRead
        self.formats = formats
    }

    public var summary: String {
        let formatList = formats.sorted().joined(separator: ", ")
        let base = "\(threads.count) threads from \(filesRead) file\(filesRead == 1 ? "" : "s")"
        return formatList.isEmpty ? base : "\(base) · \(formatList)"
    }
}

public enum ImportError: LocalizedError {
    case unsupported(String)
    case unreadable(String)
    case empty(String)
    case noFiles

    public var errorDescription: String? {
        switch self {
        case .unsupported(let detail): return detail
        case .unreadable(let file): return "Could not read \(file)."
        case .empty(let detail): return detail
        case .noFiles: return "No supported conversation export files were found."
        }
    }
}

/// Format sniffing + dispatch. Supported inputs:
///  - ChatGPT `conversations.json`
///  - Google Takeout Gemini `My Activity.json` (and best-effort HTML)
///  - Claude `conversations.json`
///  - MINDME's generic `{ "threads": [...] }` schema
public enum ConversationImporter {

    public static func importFiles(at urls: [URL]) throws -> ImportResult {
        let files = expand(urls)
        guard !files.isEmpty else { throw ImportError.noFiles }

        var result = ImportResult()
        var firstError: Error?
        let parser = ImportParser()

        for url in files {
            do {
                // SQLite stores (OpenCode) must be opened in place; they can be
                // far too large to read into memory.
                if OpenCodeImporter.isSQLiteDatabase(at: url) {
                    let parsed = try OpenCodeImporter.parse(databaseURL: url)
                    result.filesRead += 1
                    result.formats.formUnion(parsed.formats)
                    result.warnings.append(contentsOf: parsed.warnings)
                    result.threads.append(contentsOf: parsed.threads)
                    continue
                }

                let data = try Data(contentsOf: url)
                guard !data.isEmpty else {
                    result.warnings.append("\(url.lastPathComponent) is empty.")
                    continue
                }
                let parsed = try parser.parse(data: data, fileName: url.lastPathComponent)
                result.filesRead += 1
                result.formats.formUnion(parsed.formats)
                result.warnings.append(contentsOf: parsed.warnings)
                result.threads.append(contentsOf: parsed.threads)
            } catch {
                if firstError == nil { firstError = error }
                result.warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        guard !result.threads.isEmpty else {
            throw firstError ?? ImportError.empty("No conversations could be imported.")
        }
        // De-duplicate inside the batch.
        var seen: [String: Int] = [:]
        var unique: [ConversationThread] = []
        for thread in result.threads {
            if let index = seen[thread.id] {
                if thread.messages.count > unique[index].messages.count {
                    unique[index] = thread
                }
            } else {
                seen[thread.id] = unique.count
                unique.append(thread)
            }
        }
        result.threads = unique
        result.warnings = Array(Set(result.warnings)).sorted()
        return result
    }

    /// Expand folders into candidate export files. Dragging a whole Takeout
    /// folder or a ChatGPT export folder just works.
    public static func expand(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            let ext = url.pathExtension.lowercased()
            guard ["json", "html", "htm", "jsonl", "ndjson", "db", "sqlite", "sqlite3"].contains(ext) else { return }
            files.append(url)
        }

        func walk(_ directory: URL, depth: Int) {
            guard depth <= 4, files.count < 400 else { return }
            let contents = (try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for item in contents {
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    walk(item, depth: depth + 1)
                } else {
                    add(item)
                }
            }
        }

        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                walk(url, depth: 0)
            } else {
                add(url)
            }
        }
        // Prefer well-known export names when a folder contains lots of JSON.
        let prioritized = files.sorted { a, b in
            let aName = a.lastPathComponent.lowercased()
            let bName = b.lastPathComponent.lowercased()
            let aScore = aName.contains("conversations") || aName.contains("activity") ? 0 : 1
            let bScore = bName.contains("conversations") || bName.contains("activity") ? 0 : 1
            return aScore < bScore
        }
        return prioritized
    }
}

// MARK: - Dispatch

public struct ImportParser {

    public init() {}

    public func parse(data: Data, fileName: String) throws -> ImportResult {
        let lowerName = fileName.lowercased()
        if let text = String(data: data, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            return try GeminiHTMLImporter.parse(html: text, fileName: fileName)
        }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            if lowerName.hasSuffix(".jsonl") || lowerName.hasSuffix(".ndjson") {
                return try GenericImporter.parseJSONLines(data: data, fileName: fileName)
            }
            throw ImportError.unsupported(
                "\(fileName) is not valid JSON. Export conversations as JSON from the service."
            )
        }

        if let records = JSONInspect.conversationArray(from: json) {
            let sample = records.prefix(6)
            if sample.contains(where: { $0["mapping"] is [String: Any] }) {
                let threads = try ChatGPTImporter.parse(json: json, fileName: fileName)
                return ImportResult(threads: threads, filesRead: 1, formats: ["chatgpt"])
            }
            if sample.contains(where: { $0["chat_messages"] != nil }) {
                let threads = try ClaudeImporter.parse(json: json, fileName: fileName)
                return ImportResult(threads: threads, filesRead: 1, formats: ["claude"])
            }
            if sample.contains(where: { $0["titleUrl"] != nil || $0["header"] is String || $0["products"] != nil }) {
                let threads = try GeminiActivityImporter.parse(json: json, fileName: fileName)
                return ImportResult(threads: threads, filesRead: 1, formats: ["gemini-takeout"])
            }
            if sample.contains(where: { $0["messages"] != nil || $0["chat_messages"] != nil }) {
                let threads = try GenericImporter.parse(json: json, fileName: fileName)
                return ImportResult(threads: threads, filesRead: 1, formats: ["generic"])
            }
        }

        // Generic object with a threads array is handled above, but a single
        // thread object is valid too.
        if let object = json as? [String: Any],
           object["messages"] != nil || object["chat_messages"] != nil {
            let threads = try GenericImporter.parse(json: [object], fileName: fileName)
            return ImportResult(threads: threads, filesRead: 1, formats: ["generic"])
        }

        throw ImportError.unsupported(
            "\(fileName) is JSON, but not a recognized conversation export. Supported: ChatGPT, Gemini (Takeout), Claude, or the MINDME generic schema."
        )
    }
}

// MARK: - Helpers shared by importers

enum ImportSupport {
    static func messageText(from content: Any?) -> String {
        if let content = content as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dict = content as? [String: Any] {
            if let parts = dict["parts"] {
                return JSONInspect.strings(in: parts).joined(separator: "\n\n")
            }
            if let text = dict["text"] { return JSONInspect.strings(in: text).joined(separator: "\n\n") }
            if let text = dict["content"] { return JSONInspect.strings(in: text).joined(separator: "\n\n") }
        }
        if let array = content as? [Any] {
            return JSONInspect.strings(in: array).joined(separator: "\n\n")
        }
        return ""
    }

    static func title(from messages: [ChatMessage], fallback: String) -> String {
        if !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TextTools.truncated(fallback, limit: 90)
        }
        if let prompt = messages.first(where: { $0.role == .user })?.text {
            return TextTools.truncated(prompt, limit: 64)
        }
        return "Untitled conversation"
    }

    static func sortMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.sorted {
            switch ($0.timestamp, $1.timestamp) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return false
            }
        }
    }

    /// Infer the provider from an export filename if the payload is ambiguous.
    static func providerFromFileName(_ fileName: String) -> Provider {
        let name = fileName.lowercased()
        if name.contains("chatgpt") || name.contains("openai") { return .chatgpt }
        if name.contains("gemini") || name.contains("takeout") || name.contains("bard") { return .gemini }
        if name.contains("claude") || name.contains("anthropic") { return .claude }
        return .other
    }
}
