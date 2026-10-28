import Foundation

/// Parser for Anthropic's Claude data export (`conversations.json`).
public enum ClaudeImporter {

    public static func parse(json: Any, fileName: String) throws -> [ConversationThread] {
        guard let records = JSONInspect.conversationArray(from: json) else {
            throw ImportError.unsupported("\(fileName) does not contain a Claude conversation list.")
        }

        var threads: [ConversationThread] = []
        for record in records {
            guard let rawMessages = (record["chat_messages"] as? [[String: Any]])
                ?? (record["messages"] as? [[String: Any]]) else { continue }

            var messages: [ChatMessage] = []
            for (index, raw) in rawMessages.enumerated() {
                guard let role = MessageRole.parse((raw["sender"] as? String) ?? (raw["role"] as? String)) else { continue }
                let text = ImportSupport.messageText(from: raw["text"] ?? raw["content"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let id = (raw["uuid"] as? String) ?? "\(record["uuid"] as? String ?? "claude")-\(index)"
                messages.append(ChatMessage(
                    id: "claude:\(id)",
                    role: role,
                    text: text,
                    timestamp: FlexibleDate.parse(raw["created_at"] ?? raw["createdAt"])
                ))
            }
            guard !messages.isEmpty else { continue }

            let title = ImportSupport.title(from: messages, fallback: (record["name"] as? String) ?? "")
            let createdAt = FlexibleDate.parse(record["created_at"] ?? record["createdAt"])
                ?? messages.compactMap(\.timestamp).min()
                ?? Date(timeIntervalSince1970: 0)
            let updatedAt = FlexibleDate.parse(record["updated_at"] ?? record["updatedAt"])
                ?? messages.compactMap(\.timestamp).max()
                ?? createdAt
            let rawID = (record["uuid"] as? String)
                ?? (record["id"] as? String)
                ?? StableID.hex("\(title)|\(createdAt.timeIntervalSince1970)")

            var sourceURL: URL?
            if rawID.range(of: "^[0-9a-fA-F-]{20,}$", options: .regularExpression) != nil,
               rawID.contains("-") {
                sourceURL = URL(string: "https://claude.ai/chat/\(rawID)")
            }

            threads.append(ConversationThread(
                id: "claude:\(rawID)",
                provider: .claude,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                messages: messages,
                model: (record["model"] as? String) ?? (record["model_slug"] as? String),
                sourceURL: sourceURL,
                sourceFile: fileName
            ))
        }

        guard !threads.isEmpty else {
            throw ImportError.empty("No Claude conversations with readable messages were found in \(fileName).")
        }
        return threads
    }
}
