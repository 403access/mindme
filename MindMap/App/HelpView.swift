import SwiftUI
import AppKit
import MindMapCore

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        ZStack {
            Color(hex: 0x060A12)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        LogoMark()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MINDME")
                                .font(HUDFont.label(14))
                                .tracking(3.2)
                                .foregroundStyle(HUD.text)
                            Text("CONVERSATION CONSTELLATION · v0.1")
                                .font(HUDFont.micro(7.5))
                                .tracking(1.1)
                                .foregroundStyle(HUD.muted)
                        }
                        Spacer()
                        HUDIconButton(systemName: "xmark", help: "Close") { dismiss() }
                    }

                    Text("Your conversations, mapped as a living constellation. Everything is parsed and stored locally — MINDME never sends data anywhere.")
                        .font(HUDFont.body(12))
                        .foregroundStyle(HUD.textSoft)
                        .lineSpacing(3)

                    section(
                        "01", "IMPORT",
                        lines: [
                            ("CHATGPT", "Settings → Data controls → Export data. Unzip and drop conversations.json."),
                            ("GEMINI", "Google Takeout → My Activity → Gemini Apps → JSON. Drop My Activity.json or the Takeout folder."),
                            ("CLAUDE", "Settings → Privacy → Export data. Unzip and drop conversations.json."),
                            ("OPENCODE", "Use File → Import OpenCode Sessions, or drop ~/.local/share/opencode/opencode.db. The 150 most recent top-level sessions are read locally; subagent sessions are skipped."),
                            ("GENERIC", "Any JSON with { \"threads\": [{ \"title\", \"provider\", \"messages\": [{ \"role\", \"text\" }] }] }.")
                        ]
                    )

                    section(
                        "02", "LENSES",
                        lines: [
                            ("SOURCE", "Group hubs by provider: ChatGPT, Gemini, Claude, or other."),
                            ("TOPIC", "Cluster conversations by the keywords they share."),
                            ("ERA", "Group by month, quarter, or year, depending on the archive span.")
                        ]
                    )

                    section(
                        "03", "INTERACTION",
                        lines: [
                            ("PAN / ZOOM", "Drag to pan. Pinch on the trackpad to zoom. Use the + / − and scope controls in the map corner."),
                            ("3D SPACE", "Press ⌘3 or use the 2D/3D control in the map corner. Drag to orbit, Shift-drag to pan, and pinch or use + / − to move the camera."),
                            ("WORD CLOUD", "Press ⌘4 or use the CLOUD control to switch to a keyword cloud sized by how many conversations share each word. Click a word to isolate its threads."),
                            ("INSPECT", "Click any conversation node or thread in the sidebar to open its transcript."),
                            ("TAGS", "Shared keyword nodes link conversations across providers. Click one to see every thread behind it."),
                            ("FILTERS", "Combine source toggles, a time window, and a text query. The map rebuilds instantly.")
                        ]
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(index: "04", title: "KEYBOARD")
                        HStack(spacing: 6) {
                            key("⌘I", "IMPORT")
                            key("⌘F", "SEARCH")
                            key("⌘0", "FIT")
                            key("⌘R", "RELOAD")
                            key("⌘3", "3D")
                            key("⌘4", "CLOUD")
                            key("ESC", "CLOSE")
                        }
                    }

                    HStack(spacing: 8) {
                        HUDGhostButton(title: copied ? "Path copied" : "Reveal library", icon: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([
                                ThreadStore().libraryURL
                            ])
                        }
                        HUDGhostButton(title: "Close", icon: "checkmark") { dismiss() }
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 620)
        .preferredColorScheme(.dark)
    }

    private func section(_ index: String, _ title: String, lines: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(index: index, title: title)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 10) {
                        Text(line.0)
                            .font(HUDFont.micro(7.5))
                            .tracking(0.9)
                            .foregroundStyle(HUD.accent.opacity(0.75))
                            .frame(width: 62, alignment: .leading)
                        Text(line.1)
                            .font(HUDFont.body(11.5))
                            .foregroundStyle(HUD.textSoft)
                            .lineSpacing(2.5)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.022))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUD.hairline, lineWidth: 0.8))
            )
        }
    }

    private func key(_ shortcut: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(shortcut)
                .font(HUDFont.micro(8))
                .foregroundStyle(HUD.text)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(HUD.hairline, lineWidth: 0.7))
                )
            Text(label)
                .font(HUDFont.micro(6.5))
                .tracking(0.7)
                .foregroundStyle(HUD.dim)
        }
    }
}
