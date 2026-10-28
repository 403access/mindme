import Foundation

// MARK: - Stable identifiers

public enum StableID {
    /// FNV-1a 64 bit. Deterministic across launches and platforms.
    public static func hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    public static func hex(_ string: String) -> String {
        String(format: "%016llx", hash(string))
    }
}

// MARK: - Dates

public enum FlexibleDate {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let plain: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
            "MMM d, yyyy, h:mm:ss a",
            "M/d/yy, h:mm a"
        ]
        return formats.map { format in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = format
            return f
        }
    }()

    /// Parses ISO 8601, common date strings, and unix timestamps in
    /// seconds / milliseconds / nanoseconds.
    public static func parse(_ any: Any?) -> Date? {
        if let date = any as? Date { return date }
        if let number = any as? NSNumber { return fromTimestamp(number.doubleValue) }
        if let double = any as? Double { return fromTimestamp(double) }
        if let int = any as? Int { return fromTimestamp(Double(int)) }
        guard let raw = any as? String else { return nil }
        let string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }

        if let date = isoFractional.date(from: string) { return date }
        if let date = iso.date(from: string) { return date }
        for formatter in plain {
            if let date = formatter.date(from: string) { return date }
        }
        if let value = Double(string) { return fromTimestamp(value) }
        return nil
    }

    public static func fromTimestamp(_ value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        // Heuristic: exports use seconds; some tools use ms / ns.
        if value > 1e17 { return Date(timeIntervalSince1970: value / 1e9) }
        if value > 1e14 { return Date(timeIntervalSince1970: value / 1e6) }
        if value > 1e11 { return Date(timeIntervalSince1970: value / 1e3) }
        return Date(timeIntervalSince1970: value)
    }
}

// MARK: - Strings

public enum TextTools {
    public static func collapsed(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func count(_ value: Int, singular: String, plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    public static func truncated(_ string: String, limit: Int) -> String {
        let clean = collapsed(string)
        guard clean.count > limit else { return clean }
        let cut = String(clean.prefix(limit)).trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }

    public static func slug(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = string.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let raw = String(scalars)
        let parts = raw.split(separator: "-", omittingEmptySubsequences: true)
        return parts.prefix(6).joined(separator: "-")
    }

    /// Removes HTML tags and decodes the handful of entities that appear in
    /// exported conversation pages.
    public static func plainText(fromHTML html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: "<(script|style)[^>]*>.*?</\\1>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<br\\s*/?>|</p>|</div>|</li>|</h[1-6]>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&mdash;": "—",
            "&ndash;": "–", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘",
            "&ldquo;": "“", "&rdquo;": "”"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - JSON helpers

public extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        if let value = self[key] as? String { return value }
        if let number = self[key] as? NSNumber { return number.stringValue }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let value = self[key] as? Double { return value }
        if let value = self[key] as? Int { return Double(value) }
        if let value = self[key] as? NSNumber { return value.doubleValue }
        if let value = self[key] as? String { return Double(value) }
        return nil
    }

    func int(_ key: String) -> Int? {
        double(key).map { Int($0) }
    }

    func bool(_ key: String) -> Bool? {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        return nil
    }

    func object(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func objects(_ key: String) -> [[String: Any]]? {
        self[key] as? [[String: Any]]
    }

    func array(_ key: String) -> [Any]? {
        self[key] as? [Any]
    }
}

public enum JSONInspect {
    /// Recursively pulls human readable strings out of a message `parts`
    /// array. Handles strings, multimodal parts, code blocks and tool output.
    public static func strings(in value: Any?) -> [String] {
        guard let value else { return [] }
        if let string = value as? String {
            let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? [] : [clean]
        }
        if let array = value as? [Any] {
            return array.flatMap { strings(in: $0) }
        }
        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String {
                return strings(in: text)
            }
            if let text = dict["content"] { return strings(in: text) }
            if let text = dict["value"] { return strings(in: text) }
            return []
        }
        return []
    }

    public static func conversationArray(from json: Any) -> [[String: Any]]? {
        if let array = json as? [[String: Any]] { return array }
        if let object = json as? [String: Any] {
            for key in ["conversations", "threads", "chats", "items", "data"] {
                if let array = object[key] as? [[String: Any]] { return array }
            }
            // Some exports key conversations by id.
            if object.values.allSatisfy({ $0 is [String: Any] }) {
                return object.values.compactMap { $0 as? [String: Any] }
            }
        }
        return nil
    }
}
