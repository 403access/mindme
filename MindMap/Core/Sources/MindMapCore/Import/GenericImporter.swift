import Foundation

/// Accepts the MINDME generic schema so any other chat tool can be piped in:
///
/// ```json
/// { "threads": [{
///     "id": "abc", "provider": "gemini", "title": "…",
///     "createdAt": "2026-01-01T10:00:00Z",
///     "messages": [{ "role": "user", "text": "…", "timestamp": "…" }]
/// }] }
/// ```
public enum GenericImporter {

    public static func parse(json: Any, fileName: String) throws -> [ConversationThread] {
        let records: [[String: Any]]
        if let array = json as? [[String: Any]] {
            records = array
        } else if let object = json as? [String: Any] {
            if let array = (object["threads"] ?? object["conversations"] ?? object["chats"]) as? [[String: Any]] {
                records = array
            } else if object["messages"] != nil || object["chat_messages"] != nil {
                records = [object]
            } else {
                throw ImportError.unsupported("\(fileName) does not match the generic threads schema.")
            }
        } else {
            throw ImportError.unsupported("\(fileName) is not a generic conversation file.")
        }

        let fallbackProvider = ImportSupport.providerFromFileName(fileName)
        var threads: [ConversationThread] = []

        for (recordIndex, record) in records.enumerated() {
            guard let thread = parseThread(record, index: recordIndex, fileName: fileName, fallbackProvider: fallbackProvider) else {
                continue
            }
            threads.append(thread)
        }

        guard !threads.isEmpty else {
            throw ImportError.empty("No readable conversations were found in \(fileName).")
        }
        return threads
    }

    public static func parseJSONLines(data: Data, fileName: String) throws -> ImportResult {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportError.unreadable(fileName)
        }
        let lines = text.split(whereSeparator: \.isNewline)
        var threadRecords: [[String: Any]] = []
        var grouped: [String: [[String: Any]]] = [:]
        var groupOrder: [String] = []
        var warnings: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                warnings.append("Skipped a malformed JSONL line.")
                continue
            }
            if object["messages"] != nil || object["title"] != nil {
                threadRecords.append(object)
            } else if let message = object["message"] as? [String: Any] ?? object["text"] as? [String: Any] {
                let key = (object["conversation_id"] as? String)
                    ?? (object["thread_id"] as? String)
                    ?? (object["chat_id"] as? String)
                    ?? "default"
                if grouped[key] == nil {
                    grouped[key] = []
                    groupOrder.append(key)
                }
                grouped[key]?.append(message)
            }
        }

        for key in groupOrder {
            guard let messages = grouped[key], !messages.isEmpty else { continue }
            threadRecords.append([
                "id": key,
                "title": (messages.first?["title"] as? String) ?? "Imported conversation",
                "messages": messages
            ])
        }

        let threads = try parse(json: threadRecords, fileName: fileName)
        return ImportResult(threads: threads, warnings: warnings, filesRead: 1, formats: ["generic-jsonl"])
    }

    private static func parseThread(
        _ record: [String: Any],
        index: Int,
        fileName: String,
        fallbackProvider: Provider
    ) -> ConversationThread? {
        let rawMessages = (record["messages"] as? [[String: Any]])
            ?? (record["chat_messages"] as? [[String: Any]])
            ?? []

        var messages: [ChatMessage] = []
        for (messageIndex, raw) in rawMessages.enumerated() {
            let roleRaw = (raw["role"] as? String)
                ?? (raw["sender"] as? String)
                ?? ((raw["author"] as? [String: Any])?["role"] as? String)
            guard let role = MessageRole.parse(roleRaw) else { continue }
            let content = raw["text"] ?? raw["content"] ?? raw["parts"] ?? raw["message"]
            let text = ImportSupport.messageText(from: content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let id = (raw["id"] as? String)
                ?? (raw["uuid"] as? String)
                ?? "\(index)-\(messageIndex)"
            messages.append(ChatMessage(
                id: "generic:\(id)",
                role: role,
                text: text,
                timestamp: FlexibleDate.parse(raw["timestamp"] ?? raw["time"] ?? raw["created_at"] ?? raw["createdAt"])
            ))
        }
        guard !messages.isEmpty else { return nil }

        let provider = Provider.parse(
            (record["provider"] as? String)
                ?? (record["source"] as? String)
                ?? (record["service"] as? String)
        )
        let resolvedProvider = provider == .other ? fallbackProvider : provider
        let title = ImportSupport.title(
            from: messages,
            fallback: (record["title"] as? String) ?? (record["name"] as? String) ?? ""
        )
        let createdAt = FlexibleDate.parse(record["createdAt"] ?? record["created_at"] ?? record["create_time"])
            ?? messages.compactMap(\.timestamp).min()
            ?? Date(timeIntervalSince1970: 0)
        let updatedAt = FlexibleDate.parse(record["updatedAt"] ?? record["updated_at"] ?? record["update_time"])
            ?? messages.compactMap(\.timestamp).max()
            ?? createdAt
        let rawID = (record["id"] as? String)
            ?? (record["uuid"] as? String)
            ?? StableID.hex("\(title)|\(createdAt.timeIntervalSince1970)|\(index)")

        return ConversationThread(
            id: "\(resolvedProvider.rawValue):\(rawID)",
            provider: resolvedProvider,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messages: messages,
            model: (record["model"] as? String) ?? (record["model_slug"] as? String),
            sourceURL: (record["url"] as? String).flatMap(URL.init(string:)),
            sourceFile: fileName
        )
    }
}
