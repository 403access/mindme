import Foundation

/// Sidecar persistence for topic profiles. Kept separate from `library.json`
/// so re-importing conversations never destroys user-visible analysis, and a
/// stale profile can be recomputed without touching the archive.
public final class TopicStore {
    public let directory: URL
    public let analysisURL: URL
    public let taxonomyURL: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.directory = base.appendingPathComponent("MindMap", isDirectory: true)
        }
        self.analysisURL = self.directory.appendingPathComponent("topics.json")
        self.taxonomyURL = self.directory.appendingPathComponent("taxonomy.json")
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: analysisURL.path)
    }

    public func load() throws -> TopicAnalysis {
        guard exists else { return .empty }
        let data = try Data(contentsOf: analysisURL)
        guard !data.isEmpty else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TopicAnalysis.self, from: data)
    }

    public func save(_ analysis: TopicAnalysis) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(analysis)
        try data.write(to: analysisURL, options: .atomic)
    }

    public func delete() throws {
        if exists {
            try FileManager.default.removeItem(at: analysisURL)
        }
    }

    // MARK: - Editable taxonomy

    /// A user-supplied `taxonomy.json` overrides the compiled default. The
    /// default is written once so the spine can be renamed, reseeded, or
    /// extended without touching code.
    public func loadTaxonomy() -> TopicTaxonomy? {
        guard FileManager.default.fileExists(atPath: taxonomyURL.path),
              let data = try? Data(contentsOf: taxonomyURL),
              !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(TopicTaxonomy.self, from: data)
    }

    public func saveTaxonomy(_ taxonomy: TopicTaxonomy) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(taxonomy)
        try data.write(to: taxonomyURL, options: .atomic)
    }

    /// Seeds the editable copy on first run without overwriting user edits.
    public func ensureTaxonomyFile(_ taxonomy: TopicTaxonomy = .default) {
        guard !FileManager.default.fileExists(atPath: taxonomyURL.path) else { return }
        try? saveTaxonomy(taxonomy)
    }
}
