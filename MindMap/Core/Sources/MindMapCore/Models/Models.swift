import Foundation

// MARK: - Provider

public enum Provider: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case chatgpt
    case gemini
    case claude
    case opencode
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        case .opencode: return "OpenCode"
        case .other: return "Other"
        }
    }

    public var shortName: String {
        switch self {
        case .chatgpt: return "GPT"
        case .gemini: return "GEM"
        case .claude: return "CLD"
        case .opencode: return "OPC"
        case .other: return "OTH"
        }
    }

    public var order: Int {
        switch self {
        case .chatgpt: return 0
        case .gemini: return 1
        case .claude: return 2
        case .opencode: return 3
        case .other: return 4
        }
    }

    public static func parse(_ raw: String?) -> Provider {
        guard var value = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return .other }
        value = value.replacingOccurrences(of: " ", with: "")
        if value.contains("chatgpt") || value.contains("openai") || value == "gpt" { return .chatgpt }
        if value.contains("gemini") || value.contains("bard") || value.contains("google") { return .gemini }
        if value.contains("claude") || value.contains("anthropic") { return .claude }
        if value.contains("opencode") { return .opencode }
        return .other
    }
}

// MARK: - Message

public enum MessageRole: String, Codable, Hashable, Sendable {
    case user
    case assistant
    case system
    case tool

    public var label: String {
        switch self {
        case .user: return "USER"
        case .assistant: return "ASSISTANT"
        case .system: return "SYSTEM"
        case .tool: return "TOOL"
        }
    }

    public var isPrompt: Bool { self == .user }

    public static func parse(_ raw: String?) -> MessageRole? {
        guard let value = raw?.lowercased() else { return nil }
        if value == "user" || value == "human" || value == "prompt" { return .user }
        if value == "assistant" || value == "ai" || value == "model" || value == "bot" { return .assistant }
        if value == "system" { return .system }
        if value == "tool" || value == "function" { return .tool }
        return nil
    }
}

public struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var role: MessageRole
    public var text: String
    public var timestamp: Date?

    public init(id: String, role: MessageRole, text: String, timestamp: Date? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

// MARK: - ConversationThread

public struct ConversationThread: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var provider: Provider
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [ChatMessage]
    public var model: String?
    public var sourceURL: URL?
    public var sourceFile: String?
    public var isDemo: Bool

    public init(
        id: String,
        provider: Provider,
        title: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        messages: [ChatMessage],
        model: String? = nil,
        sourceURL: URL? = nil,
        sourceFile: String? = nil,
        isDemo: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? messages.compactMap(\.timestamp).max() ?? createdAt
        self.messages = messages
        self.model = model
        self.sourceURL = sourceURL
        self.sourceFile = sourceFile
        self.isDemo = isDemo
    }

    public var messageCount: Int { messages.count }
    public var userMessageCount: Int { messages.filter { $0.role == .user }.count }

    public var characterCount: Int {
        messages.reduce(0) { $0 + $1.text.count }
    }

    public var wordCount: Int {
        messages.reduce(0) { partial, message in
            partial + message.text.split(whereSeparator: { $0.isWhitespace }).count
        }
    }

    public var preview: String {
        let prompt = messages.first(where: { $0.role == .user })?.text
            ?? messages.first?.text
            ?? ""
        return TextTools.truncated(prompt, limit: 180)
    }

    /// Best-effort link back to the original conversation.
    public var deepLink: URL? {
        if let sourceURL { return sourceURL }
        switch provider {
        case .chatgpt:
            let uuid = id.replacingOccurrences(of: "chatgpt:", with: "")
            guard uuid.count >= 20, uuid.contains("-") else { return nil }
            return URL(string: "https://chatgpt.com/c/\(uuid)")
        case .claude:
            let uuid = id.replacingOccurrences(of: "claude:", with: "")
            guard uuid.count >= 20, uuid.contains("-") else { return nil }
            return URL(string: "https://claude.ai/chat/\(uuid)")
        default:
            return nil
        }
    }

    public var dateRange: ClosedRange<Date>? {
        let dates = messages.compactMap(\.timestamp)
        guard let min = dates.min(), let max = dates.max() else { return nil }
        return min...max
    }
}

// MARK: - Library

public struct ThreadLibrary: Codable, Sendable {
    public var threads: [ConversationThread]
    public var lastImport: Date?

    public init(threads: [ConversationThread] = [], lastImport: Date? = nil) {
        self.threads = threads
        self.lastImport = lastImport
    }

    public static let empty = ThreadLibrary()

    public var demoThreadCount: Int { threads.filter(\.isDemo).count }
    public var hasDemoData: Bool { demoThreadCount > 0 }

    public var providerCounts: [Provider: Int] {
        Dictionary(grouping: threads, by: \.provider).mapValues(\.count)
    }

    public var earliestDate: Date? { threads.map(\.createdAt).min() }
    public var latestDate: Date? { threads.map(\.updatedAt).max() }
    public var messageCount: Int { threads.reduce(0) { $0 + $1.messageCount } }

    public mutating func removeDemoData() {
        threads.removeAll(where: \.isDemo)
    }

    /// Merge imported threads. Existing threads with the same id are replaced
    /// when the incoming copy is newer or has more content.
    @discardableResult
    public mutating func merge(_ incoming: [ConversationThread]) -> (added: Int, updated: Int) {
        var indexByID = Dictionary(uniqueKeysWithValues: threads.enumerated().map { ($0.element.id, $0.offset) })
        var added = 0
        var updated = 0
        for thread in incoming {
            if let index = indexByID[thread.id] {
                let existing = threads[index]
                if thread.updatedAt > existing.updatedAt || thread.messages.count > existing.messages.count {
                    threads[index] = thread
                }
                updated += 1
            } else {
                indexByID[thread.id] = threads.count
                threads.append(thread)
                added += 1
            }
        }
        threads.sort { $0.updatedAt > $1.updatedAt }
        return (added, updated)
    }
}
