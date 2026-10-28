import Foundation

/// Parser for Google Takeout's `My Activity/Gemini Apps/My Activity.json`.
///
/// Takeout activity records contain prompts (usually without model responses)
/// and sometimes a link back to the conversation. Records are grouped by
/// conversation link, or by day when no link exists, so the map doesn't fill up
/// with single-prompt fragments.
public enum GeminiActivityImporter {

    private static let genericTitles: Set<String> = [
        "used gemini apps", "used gemini", "gemini apps", "my activity", "visited gemini apps"
    ]

    public static func parse(json: Any, fileName: String) throws -> [ConversationThread] {
        let records: [[String: Any]]
        if let array = json as? [[String: Any]] {
            records = array
        } else if let object = json as? [String: Any],
                  let array = object["items"] as? [[String: Any]] {
            records = array
        } else {
            throw ImportError.unsupported("\(fileName) is not a Gemini activity export.")
        }

        struct Bucket {
            var url: URL?
            var messages: [ChatMessage] = []
            var titles: [String] = []
        }

        var buckets: [String: Bucket] = [:]
        var order: [String] = []
        var dayFormatter: DateFormatter {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyy-MM-dd"
            return f
        }

        for (index, record) in records.enumerated() {
            let header = (record["header"] as? String)?.lowercased() ?? ""
            let products = (record["products"] as? [String] ?? []).map { $0.lowercased() }
            let looksGemini = header.contains("gemini") || products.contains(where: { $0.contains("gemini") })
            if !looksGemini && !fileName.lowercased().contains("gemini") { continue }

            let title = (record["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let time = FlexibleDate.parse(record["time"])
            let prompt = extractPrompt(from: record)
            guard prompt != nil || time != nil else { continue }

            let urlString = (record["titleUrl"] as? String) ?? (record["url"] as? String)
            let isConversationLink = urlString?.contains("gemini.google.com") == true
            let key: String
            if isConversationLink, let urlString {
                key = urlString.components(separatedBy: "?").first ?? urlString
            } else {
                key = "activity-\(dayFormatter.string(from: time ?? Date(timeIntervalSince1970: 0)))"
            }

            if buckets[key] == nil {
                buckets[key] = Bucket(url: isConversationLink ? URL(string: urlString ?? "") : nil)
                order.append(key)
            }
            let messageID = StableID.hex("\(key)|\(index)|\(title)|\(time?.timeIntervalSince1970 ?? 0)")
            if let prompt {
                buckets[key]?.messages.append(ChatMessage(
                    id: "gemini:\(messageID)",
                    role: .user,
                    text: prompt,
                    timestamp: time
                ))
            }
            if !title.isEmpty && !genericTitles.contains(title.lowercased()) {
                buckets[key]?.titles.append(title)
            }
        }

        var threads: [ConversationThread] = []
        for key in order {
            guard let bucket = buckets[key], !bucket.messages.isEmpty else { continue }
            let messages = ImportSupport.sortMessages(bucket.messages)
            let titleSource = bucket.titles.first ?? messages.first?.text ?? ""
            let title = TextTools.truncated(
                stripPromptPrefix(titleSource).isEmpty ? (messages.first?.text ?? "Gemini activity") : stripPromptPrefix(titleSource),
                limit: 80
            )
            let created = messages.compactMap(\.timestamp).min() ?? Date(timeIntervalSince1970: 0)
            let updated = messages.compactMap(\.timestamp).max() ?? created
            threads.append(ConversationThread(
                id: "gemini:\(StableID.hex(key))",
                provider: .gemini,
                title: title.isEmpty ? "Gemini activity" : title,
                createdAt: created,
                updatedAt: updated,
                messages: messages,
                sourceURL: bucket.url,
                sourceFile: fileName
            ))
        }

        guard !threads.isEmpty else {
            throw ImportError.empty(
                "No Gemini prompts were found in \(fileName). Make sure it is the Gemini Apps activity export (JSON), not a different Google product."
            )
        }
        return threads
    }

    private static func extractPrompt(from record: [String: Any]) -> String? {
        if let details = record["details"] as? [[String: Any]] {
            for detail in details {
                if let text = detail["text"] as? String {
                    let clean = stripPromptPrefix(text)
                    if !clean.isEmpty { return clean }
                }
            }
        }
        if let title = record["title"] as? String {
            let clean = stripPromptPrefix(title)
            if !clean.isEmpty && !genericTitles.contains(clean.lowercased()) {
                return clean
            }
        }
        if let subtitles = record["subtitles"] as? [[String: Any]] {
            for subtitle in subtitles {
                if let text = subtitle["name"] as? String {
                    let clean = stripPromptPrefix(text)
                    if !clean.isEmpty && !genericTitles.contains(clean.lowercased()) {
                        return clean
                    }
                }
            }
        }
        return nil
    }

    private static func stripPromptPrefix(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "Said ", "Prompted ", "Asked ", "Searched for ", "Used Gemini Apps to ",
            "You said ", "You asked "
        ]
        for prefix in prefixes where value.lowercased().hasPrefix(prefix.lowercased()) {
            value = String(value.dropFirst(prefix.count))
            break
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”„ "))
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
