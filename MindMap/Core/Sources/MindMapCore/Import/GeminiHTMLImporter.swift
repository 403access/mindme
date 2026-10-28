import Foundation

/// Best-effort parser for Google Takeout's HTML conversation exports.
/// The official JSON activity export is preferred and more complete; HTML is
/// accepted so dragging a Takeout folder still produces something useful.
public enum GeminiHTMLImporter {

    public static func parse(html: String, fileName: String) throws -> ImportResult {
        let title = extractTitle(html) ?? "Gemini conversation"
        let blocks = extractBlocks(html)

        guard !blocks.isEmpty else {
            throw ImportError.unsupported(
                "\(fileName) is an HTML export without recognizable Gemini message blocks. Prefer the JSON activity export (My Activity.json) from Google Takeout."
            )
        }

        var messages: [ChatMessage] = []
        for (index, block) in blocks.enumerated() {
            let text = TextTools.plainText(fromHTML: block.html)
            let clean = TextTools.collapsed(text)
            guard clean.count >= 2 else { continue }
            let role: MessageRole = block.isPrompt ? .user : .assistant
            messages.append(ChatMessage(
                id: "gemini-html:\(StableID.hex("\(fileName)|\(index)|\(clean.prefix(40))"))",
                role: role,
                text: clean,
                timestamp: block.timestamp
            ))
        }

        guard messages.contains(where: { $0.role == .user }) || !messages.isEmpty else {
            throw ImportError.empty("No messages could be read from \(fileName).")
        }

        let date = messages.compactMap(\.timestamp).min() ?? Date()
        let thread = ConversationThread(
            id: "gemini:\(StableID.hex("\(fileName)|\(title)|\(date.timeIntervalSince1970)"))",
            provider: .gemini,
            title: TextTools.truncated(title, limit: 90),
            createdAt: date,
            updatedAt: messages.compactMap(\.timestamp).max() ?? date,
            messages: messages,
            sourceFile: fileName
        )
        return ImportResult(threads: [thread], filesRead: 1, formats: ["gemini-html"])
    }

    private struct Block {
        var html: String
        var isPrompt: Bool
        var timestamp: Date?
    }

    private static func extractTitle(_ html: String) -> String? {
        guard let range = html.range(of: "<title[^>]*>(.*?)</title>", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let raw = String(html[range])
        let inner = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let decoded = TextTools.plainText(fromHTML: inner)
        let cleaned = decoded
            .replacingOccurrences(of: " - Gemini", with: "")
            .replacingOccurrences(of: "Gemini - ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func extractBlocks(_ html: String) -> [Block] {
        let pattern = #"<(div|p|span|section)[^>]*class="[^"]*(query-text|user-query|model-response-text|response-text|message-content)[^"]*"[^>]*>(.*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var blocks: [Block] = []
        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let classRange = match.range(at: 2)
            let bodyRange = match.range(at: 3)
            guard classRange.location != NSNotFound, bodyRange.location != NSNotFound else { continue }
            let className = ns.substring(with: classRange).lowercased()
            let body = ns.substring(with: bodyRange)
            let isPrompt = className.contains("query") || className.contains("user")
            let timestamp = extractTimestamp(near: match.range.location, in: html)
            blocks.append(Block(html: body, isPrompt: isPrompt, timestamp: timestamp))
        }
        // Drop duplicates produced by nested markup with the same text.
        var seen = Set<String>()
        return blocks.filter { block in
            let key = TextTools.collapsed(TextTools.plainText(fromHTML: block.html)).lowercased()
            guard key.count > 3 else { return false }
            return seen.insert(key).inserted
        }
    }

    private static func extractTimestamp(near location: Int, in html: String) -> Date? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))"#,
            options: []
        ) else { return nil }
        let ns = html as NSString
        let windowStart = max(0, location - 600)
        let windowLength = min(ns.length - windowStart, 1200)
        guard windowLength > 0 else { return nil }
        let matches = regex.matches(in: html, range: NSRange(location: windowStart, length: windowLength))
        return matches.first.flatMap { FlexibleDate.parse(ns.substring(with: $0.range(at: 1))) }
    }
}
