import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Local, JSON-file backed library. Conversation exports never leave the Mac:
/// everything is normalized and stored in Application Support.
public final class ThreadStore {
    public let directory: URL
    public let libraryURL: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                    .appendingPathComponent("Library/Application Support")
            self.directory = base.appendingPathComponent("MindMap", isDirectory: true)
        }
        self.libraryURL = self.directory.appendingPathComponent("library.json")
    }

    public func load() throws -> ThreadLibrary {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: libraryURL)
        guard !data.isEmpty else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var library = try decoder.decode(ThreadLibrary.self, from: data)
        library.threads.sort { $0.updatedAt > $1.updatedAt }
        return library
    }

    public func save(_ library: ThreadLibrary) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(library)
        try data.write(to: libraryURL, options: .atomic)
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: libraryURL.path)
    }

    public func revealInFinder() {
        #if canImport(AppKit)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([libraryURL])
        #endif
    }

    public func deleteLibrary() throws {
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            try FileManager.default.removeItem(at: libraryURL)
        }
    }
}
