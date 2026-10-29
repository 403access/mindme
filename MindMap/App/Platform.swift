import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Platform shims

/// Small abstractions over the handful of AppKit-only touches in the shared UI.
enum Platform {
    static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static var isAppActive: Bool {
        #if os(macOS)
        NSApp.isActive
        #elseif os(iOS)
        UIApplication.shared.applicationState == .active
        #else
        true
        #endif
    }

    /// Text measurement shared by the word-cloud layouts. The layout modules
    /// are UI-framework neutral, so this is the one place that knows whether
    /// the host is AppKit or UIKit.
    static func measureText(_ term: String, font size: CGFloat) -> CGSize {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        #elseif os(iOS)
        let font = UIFont.systemFont(ofSize: size, weight: .semibold)
        #endif
        return (term as NSString).size(withAttributes: [.font: font])
    }

    static func setPointer(hand: Bool) {
        #if os(macOS)
        if hand {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
        #endif
    }

    static func dismissKeyboard() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #elseif os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    static func revealLibrary(at url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #elseif os(iOS)
        UIPasteboard.general.string = url.path
        #endif
    }
}

// MARK: - View helpers

extension View {
    /// `onExitCommand` is macOS-only; iOS gets the same behaviour from its own
    /// navigation chrome (sheets, the inspector close button).
    @ViewBuilder
    func dismissOnEscape(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        self.onExitCommand(perform: action)
        #else
        self
        #endif
    }

    @ViewBuilder
    func windowDragHandle() -> some View {
        #if os(macOS)
        self.background(WindowDragHandle())
        #else
        self
        #endif
    }

    @ViewBuilder
    func disableAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self
        #endif
    }
}

// MARK: - Export

/// Lightweight `FileDocument` used by the iOS export sheet. It carries the
/// same normalized library JSON the macOS save panel writes for the Quest
/// viewer, so both platforms produce identical files.
struct QuestLibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum ImportPickerTypes {
    /// Files the importer understands, plus folders so a whole Takeout or
    /// ChatGPT export directory can be picked from the Files app.
    static var allowed: [UTType] {
        var types: [UTType] = [.json, .html, .plainText, .folder]
        for ext in ["db", "sqlite", "sqlite3", "jsonl", "ndjson"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }
}
