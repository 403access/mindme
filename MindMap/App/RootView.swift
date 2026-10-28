import SwiftUI
import UniformTypeIdentifiers
import AppKit
import MindMapCore

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var dropTargeted = false
    @State private var dropURLs: [URL] = []
    @State private var dropGroup: DispatchGroup?

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 0) {
                TopBarView(model: model)

                HStack(spacing: 12) {
                    SidebarView(model: model)
                        .frame(width: 282)

                    ZStack {
                        MapBackdrop()
                        GraphCanvasView(model: model, engine: model.engine)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let node = model.selectedNode {
                        DetailPanelView(model: model, node: node)
                            .frame(width: 348)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 8)
                .animation(.spring(response: 0.38, dampingFraction: 0.88), value: model.selectedNodeID)

                StatusBarView(model: model, engine: model.engine)
            }

            if let toast = model.toast {
                VStack {
                    Spacer()
                    ToastView(toast: toast, dismiss: model.dismissToast)
                        .padding(.bottom, 52)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(20)
            }

            if dropTargeted {
                DropOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(30)
            }
        }
        .background(HUD.void)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onExitCommand { model.deselect() }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .sheet(isPresented: $model.showHelp) {
            HelpView()
        }
        .alert("Reset local library?", isPresented: $model.showResetConfirmation) {
            Button("Reset everything", role: .destructive) {
                model.resetEverything()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the normalized library from this Mac. Your original export files are untouched.")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let box = URLBox()
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                } else if let string = item as? String {
                    url = URL(string: string)
                }
                if let url { box.add(url) }
            }
        }
        group.notify(queue: .main) {
            let urls = box.urls
            guard !urls.isEmpty else { return }
            model.importFiles(urls)
        }
        return true
    }
}

private final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func add(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(url)
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

// MARK: - Window drag

struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Backdrop

struct AppBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x05070C), Color(hex: 0x070B13), Color(hex: 0x04060A)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [HUD.accent.opacity(0.055), .clear],
                center: .init(x: 0.55, y: 0.15),
                startRadius: 0,
                endRadius: 720
            )
            RadialGradient(
                colors: [HUD.magenta.opacity(0.035), .clear],
                center: .init(x: 0.95, y: 0.85),
                startRadius: 0,
                endRadius: 620
            )
            // Fine scanline texture.
            Canvas { context, size in
                var path = Path()
                var y: CGFloat = 0
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += 3
                }
                context.stroke(path, with: .color(Color.white.opacity(0.008)), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Top bar

struct TopBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            LogoMark()

            Text("MINDME")
                .font(HUDFont.label(13.5))
                .tracking(3.8)
                .foregroundStyle(HUD.text)

            Rectangle()
                .fill(HUD.hairline)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            HStack(spacing: 6) {
                Text("NEXUS")
                    .font(HUDFont.micro(8))
                    .tracking(1.4)
                    .foregroundStyle(HUD.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(HUD.dim)
                Text(model.grouping.label)
                    .font(HUDFont.micro(8))
                    .tracking(1.4)
                    .foregroundStyle(HUD.accent.opacity(0.85))
                if model.library.hasDemoData {
                    Text("DEMO")
                        .font(HUDFont.micro(7))
                        .tracking(0.8)
                        .foregroundStyle(HUD.amber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(HUD.amber.opacity(0.10))
                                .overlay(Capsule().strokeBorder(HUD.amber.opacity(0.38), lineWidth: 0.7))
                        )
                        .padding(.leading, 2)
                }
            }

            Spacer(minLength: 8)

            if model.isImporting {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                    Text("PARSING EXPORT")
                        .font(HUDFont.micro(8))
                        .tracking(1)
                        .foregroundStyle(HUD.accent)
                }
                .padding(.trailing, 4)
            }

            HStack(spacing: 10) {
                metric(value: "\(model.library.threads.count)", label: "THREADS")
                metric(value: Format.compactCount(model.library.messageCount), label: "MESSAGES")
                metric(value: "\(model.graph.stats.tagCount)", label: "TAGS")
            }
            .padding(.horizontal, 4)

            Rectangle().fill(HUD.hairline).frame(width: 1, height: 18)

            HUDIconButton(systemName: "scope", help: "Fit map  ⌘0") {
                model.engine.requestFit()
            }
            HUDIconButton(systemName: "square.and.arrow.down", help: "Import exports  ⌘I") {
                model.presentImportPanel()
            }
            HUDIconButton(systemName: "arrow.clockwise", help: "Reload library  ⌘R") {
                model.reloadLibrary()
            }
            HUDIconButton(systemName: "questionmark", help: "Help & formats") {
                model.showHelp = true
            }
        }
        .padding(.leading, 98)
        .padding(.trailing, 18)
        .frame(height: 52)
        .background(WindowDragHandle())
    }

    private func metric(value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(HUDFont.micro(9.5))
                .tracking(0.3)
                .foregroundStyle(HUD.text.opacity(0.92))
                .contentTransition(.numericText())
            Text(label)
                .font(HUDFont.micro(7))
                .tracking(0.9)
                .foregroundStyle(HUD.muted)
        }
    }
}

struct LogoMark: View {
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            HexagonShape()
                .stroke(
                    LinearGradient(
                        colors: [HUD.accent, HUD.accent.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .frame(width: 22, height: 22)
            HexagonShape()
                .trim(from: 0.05, to: 0.38)
                .stroke(HUD.magenta.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(phase))
            Circle()
                .fill(HUD.accent)
                .frame(width: 3.4, height: 3.4)
                .shadow(color: HUD.accent, radius: 4)
        }
        .frame(width: 28, height: 28)
        .onAppear {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                phase = 360
            }
        }
    }
}

struct HexagonShape: Shape {
    var rotation: Angle = .degrees(0)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for index in 0..<6 {
            let angle = rotation.radians + Double(index) / 6 * 2 * .pi
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: GraphEngine

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                StatusDot(color: engine.frame.isSettling ? HUD.accent : HUD.lime, size: 4.5)
                Text(engine.frame.isSettling ? "SIMULATING" : "SIGNAL STABLE")
                    .font(HUDFont.micro(7.5))
                    .tracking(1.2)
                    .foregroundStyle(engine.frame.isSettling ? HUD.accent.opacity(0.8) : HUD.muted)
            }

            Rectangle().fill(HUD.hairline).frame(width: 1, height: 10)

            Text("\(Format.count(model.graph.nodes.count, "NODE", "NODES")) · \(Format.count(model.graph.edges.count, "LINK", "LINKS")) · \(Format.count(model.graph.stats.groupCount, "HUB", "HUBS"))")
                .font(HUDFont.micro(7.5))
                .tracking(0.7)
                .foregroundStyle(HUD.muted)

            if let summary = model.lastImportSummary {
                Text("· \(summary)")
                    .font(HUDFont.micro(7.5))
                    .tracking(0.7)
                    .foregroundStyle(HUD.textSoft.opacity(0.7))
            }

            if !model.searchText.isEmpty {
                Text("· QUERY MATCHES \(model.visibleThreads.count)")
                    .font(HUDFont.micro(7.5))
                    .tracking(0.7)
                    .foregroundStyle(HUD.amber.opacity(0.9))
            }

            Spacer()

            Text("⌘F SEARCH   ⌘I IMPORT   ⌘0 FIT   ESC CLOSE")
                .font(HUDFont.micro(7))
                .tracking(0.6)
                .foregroundStyle(HUD.dim)

            Rectangle().fill(HUD.hairline).frame(width: 1, height: 10)

            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 6.5, weight: .bold))
                Text("LOCAL ONLY")
                    .font(HUDFont.micro(7))
                    .tracking(0.9)
            }
            .foregroundStyle(HUD.lime.opacity(0.65))

            Text("v0.1")
                .font(HUDFont.micro(7))
                .foregroundStyle(HUD.dim)
        }
        .padding(.horizontal, 22)
        .frame(height: 26)
    }
}

// MARK: - Toast

struct ToastView: View {
    var toast: ToastMessage
    var dismiss: () -> Void

    private var tint: Color {
        switch toast.kind {
        case .info: return HUD.accent
        case .success: return HUD.lime
        case .error: return Color(hex: 0xFF6B7A)
        }
    }

    private var icon: String {
        switch toast.kind {
        case .info: return "waveform.path.ecg"
        case .success: return "checkmark.seal"
        case .error: return "exclamationmark.triangle"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.text)
                    .font(HUDFont.body(11.5))
                    .foregroundStyle(HUD.text)
                if let detail = toast.detail {
                    Text(detail)
                        .font(HUDFont.micro(8))
                        .foregroundStyle(HUD.muted)
                        .lineLimit(2)
                }
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(HUD.muted)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0x070D17).opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.4), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        )
    }
}

// MARK: - Drop overlay

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color(hex: 0x04060B).opacity(0.72)
                .ignoresSafeArea()
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(HUD.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                .padding(24)
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 34, weight: .thin))
                    .foregroundStyle(HUD.accent)
                Text("RELEASE TO INGEST")
                    .font(HUDFont.label(14))
                    .tracking(3)
                    .foregroundStyle(HUD.text)
                Text("ChatGPT · Gemini Takeout · Claude · MINDME JSON")
                    .font(HUDFont.micro(8.5))
                    .tracking(1)
                    .foregroundStyle(HUD.muted)
            }
        }
    }
}
