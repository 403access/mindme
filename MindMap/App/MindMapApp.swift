import SwiftUI
import AppKit
import MindMapCore

@main
struct MindMapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MINDME") {
            RootView(model: model)
                .frame(minWidth: 1120, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1460, height: 920)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.titlebarAppearsTransparent = true
                window.backgroundColor = NSColor(red: 0.016, green: 0.024, blue: 0.043, alpha: 1)
                window.isMovableByWindowBackground = false
                window.minSize = NSSize(width: 1120, height: 720)
                window.collectionBehavior.insert(.moveToActiveSpace)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .importExport) {
            Button("Import Conversations…") {
                model.presentImportPanel()
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Import OpenCode Sessions…") {
                model.importOpenCodeSessions()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Reload Library") {
                model.reloadLibrary()
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Reveal Library in Finder") {
                model.revealLibrary()
            }

            Button("Load Demo Dataset") {
                model.loadDemoData()
            }

            Button("Clear Demo Data") {
                model.clearDemoData()
            }
            .disabled(!model.library.hasDemoData)

            Divider()

            Button("Reset Local Library…") {
                model.showResetConfirmation = true
            }
        }

        CommandMenu("Map") {
            Button("Fit Map") {
                model.engine.requestFit()
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("Reset Camera") {
                model.engine.resetCamera()
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])

            Button("Deselect") {
                model.deselect()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(model.selectedNodeID == nil)

            Divider()

            Button("Search Threads") {
                model.focusSearch()
            }
            .keyboardShortcut("f", modifiers: .command)

            Divider()

            Toggle("Show Tags", isOn: $model.showTags)
            Toggle("Show Labels", isOn: $model.showLabels)
            Toggle("Ambient Motion", isOn: $model.motionEnabled)

            Divider()

            Picker("Group By", selection: $model.grouping) {
                ForEach(GroupingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
        }

        CommandGroup(replacing: .help) {
            Button("MINDME Help") {
                model.showHelp = true
            }
        }
    }
}
