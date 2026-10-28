import Foundation

/// Parser for OpenAI's ChatGPT data export (`conversations.json`).
///
/// The export stores conversations as a node tree (`mapping`) plus a
/// `current_node` pointer. We reconstruct the active branch by walking parents
/// from the current node, which avoids pulling in regenerated / abandoned
/// branches.
public enum ChatGPTImporter {

    public static func parse(json: Any, fileName: String) throws -> [ConversationThread] {
        guard let records = JSONInspect.conversationArray(from: json) else {
            throw ImportError.unsupported("\(fileName) does not contain a ChatGPT conversation list.")
        }

        var threads: [ConversationThread] = []
        for record in records {
            guard let mapping = record["mapping"] as? [String: Any] else { continue }
            if let thread = parseConversation(record, mapping: mapping, fileName: fileName) {
                threads.append(thread)
            }
        }

        guard !threads.isEmpty else {
            throw ImportError.empty("No ChatGPT conversations with readable messages were found in \(fileName).")
        }
        return threads
    }

    private static func parseConversation(
        _ record: [String: Any],
        mapping: [String: Any],
        fileName: String
    ) -> ConversationThread? {
        let currentNode = record["current_node"] as? String
            ?? record["currentNode"] as? String
            ?? leafNode(in: mapping)

        var chain: [(id: String, node: [String: Any])] = []
        var visited = Set<String>()
        var cursor = currentNode
        while let id = cursor, let raw = mapping[id] as? [String: Any], visited.insert(id).inserted {
            chain.append((id, raw))
            cursor = raw["parent"] as? String
        }
        chain.reverse()
        if chain.isEmpty {
            chain = mapping.compactMap { key, value in
                (value as? [String: Any]).map { (key, $0) }
            }
        }

        var messages: [ChatMessage] = []
        var model: String?
        var conversationModel: String?

        for (nodeID, node) in chain {
            guard let message = node["message"] as? [String: Any] else { continue }
            let metadata = message["metadata"] as? [String: Any]
            if metadata?["is_visually_hidden_from_conversation"] as? Bool == true { continue }

            let author = message["author"] as? [String: Any]
            guard let role = MessageRole.parse(author?["role"] as? String) else { continue }
            let text = ImportSupport.messageText(from: message["content"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if let slug = metadata?["model_slug"] as? String, !slug.isEmpty {
                if role == .assistant { model = slug }
                conversationModel = conversationModel ?? slug
            }

            let messageID = (message["id"] as? String) ?? nodeID
            messages.append(ChatMessage(
                id: "chatgpt:\(messageID)",
                role: role,
                text: text,
                timestamp: FlexibleDate.parse(message["create_time"])
            ))
        }

        guard messages.contains(where: { $0.role == .user || $0.role == .assistant }) else { return nil }

        let title = ImportSupport.title(
            from: messages,
            fallback: (record["title"] as? String) ?? ""
        )
        let createdAt = FlexibleDate.parse(record["create_time"])
            ?? messages.compactMap(\.timestamp).min()
            ?? Date(timeIntervalSince1970: 0)
        let updatedAt = FlexibleDate.parse(record["update_time"])
            ?? messages.compactMap(\.timestamp).max()
            ?? createdAt
        let rawID = (record["conversation_id"] as? String)
            ?? (record["id"] as? String)
            ?? currentNode
            ?? StableID.hex("\(title)|\(createdAt.timeIntervalSince1970)")
        let threadID = "chatgpt:\(rawID)"

        var sourceURL: URL?
        if rawID.range(of: "^[0-9a-fA-F-]{20,}$", options: .regularExpression) != nil {
            sourceURL = URL(string: "https://chatgpt.com/c/\(rawID)")
        }

        return ConversationThread(
            id: threadID,
            provider: .chatgpt,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messages: messages,
            model: model ?? conversationModel,
            sourceURL: sourceURL,
            sourceFile: fileName
        )
    }

    /// Last node in the tree when `current_node` is missing.
    private static func leafNode(in mapping: [String: Any]) -> String? {
        var parents = Set<String>()
        var nodes: [(id: String, node: [String: Any])] = []
        for (key, value) in mapping {
            guard let node = value as? [String: Any] else { continue }
            nodes.append((key, node))
            if let parent = node["parent"] as? String { parents.insert(parent) }
        }
        return nodes.first(where: { !parents.contains($0.id) })?.id
    }
}
