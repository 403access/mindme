#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import MindMapCore

/// Compact, touch-first presentation of the constellation. The macOS app keeps
/// its three-column window layout; on iPhone and iPad the map stays full screen
/// and the filter matrix and inspector arrive as sheets.
struct MobileRootView: View {
    @ObservedObject var model: AppModel

    @State private var showFilters = false

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { model.selectedNode != nil },
            set: { presented in
                if !presented { model.deselect() }
            }
        )
    }

    private var exportPresented: Binding<Bool> {
        Binding(
            get: { model.exportPayload != nil },
            set: { presented in
                if !presented { model.exportPayload = nil }
            }
        )
    }

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 0) {
                MobileTopBar(model: model, showFilters: $showFilters)
                map
            }

            if let toast = model.toast {
                VStack {
                    Spacer()
                    ToastView(toast: toast, dismiss: model.dismissToast)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .background(HUD.void)
        .sheet(isPresented: $showFilters) {
            MobileFiltersSheet(model: model)
        }
        .sheet(isPresented: inspectorPresented, onDismiss: { model.deselect() }) {
            if let node = model.selectedNode {
                DetailPanelView(model: model, node: node)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(HUD.void)
            }
        }
        .sheet(isPresented: $model.showHelp) {
            HelpView()
        }
        .fileImporter(
            isPresented: $model.showImportPicker,
            allowedContentTypes: ImportPickerTypes.allowed,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.importFiles(urls)
            case .failure(let error):
                model.showToast("Import failed", detail: error.localizedDescription, kind: .error)
            }
        }
        .fileExporter(
            isPresented: exportPresented,
            document: QuestLibraryDocument(data: model.exportPayload ?? Data()),
            contentType: .json,
            defaultFilename: "mindme-library"
        ) { result in
            model.handleExportResult(result)
        }
        .alert("Reset local library?", isPresented: $model.showResetConfirmation) {
            Button("Reset everything", role: .destructive) {
                model.resetEverything()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the normalized library from this device. Your original export files are untouched.")
        }
    }

    private var map: some View {
        ZStack {
            MapBackdrop()
            if model.viewMode == .cloud {
                WordCloudView(model: model)
                    .transition(.opacity)
            } else {
                GraphCanvasView(model: model, engine: model.engine)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.22), value: model.viewMode)
    }
}

// MARK: - Top bar

struct MobileTopBar: View {
    @ObservedObject var model: AppModel
    @Binding var showFilters: Bool

    var body: some View {
        HStack(spacing: 9) {
            LogoMark()

            VStack(alignment: .leading, spacing: 1) {
                Text("MINDME")
                    .font(HUDFont.label(12))
                    .tracking(3)
                    .foregroundStyle(HUD.text)
                Text("\(model.library.threads.count) THREADS · \(Format.compactCount(model.library.messageCount)) MSG")
                    .font(HUDFont.micro(6.5))
                    .tracking(0.7)
                    .foregroundStyle(HUD.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if model.isImporting {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            HUDIconButton(systemName: "line.3.horizontal.decrease", help: "Filters") {
                showFilters = true
            }
            HUDIconButton(systemName: "square.and.arrow.down", help: "Import exports") {
                model.presentImportPanel()
            }
            menu
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(HUD.deep.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(HUD.hairline).frame(height: 0.6)
        }
    }

    private var menu: some View {
        Menu {
            Button {
                model.reloadLibrary()
            } label: {
                Label("Reload Library", systemImage: "arrow.clockwise")
            }

            Button {
                model.loadDemoData()
            } label: {
                Label("Load Demo Dataset", systemImage: "sparkles")
            }

            if model.library.hasDemoData {
                Button {
                    model.clearDemoData()
                } label: {
                    Label("Clear Demo Data", systemImage: "trash")
                }
            }

            Button {
                model.exportLibraryForQuest()
            } label: {
                Label("Export Library for Quest…", systemImage: "square.and.arrow.up")
            }
            .disabled(model.library.threads.isEmpty)

            Divider()

            Button {
                model.showHelp = true
            } label: {
                Label("Help & Formats", systemImage: "questionmark.circle")
            }

            Button(role: .destructive) {
                model.showResetConfirmation = true
            } label: {
                Label("Reset Local Library…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(HUD.textSoft)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(HUD.hairline, lineWidth: 0.8)
                        )
                )
        }
    }
}

// MARK: - Filters sheet

struct MobileFiltersSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SidebarView(model: model, importAction: {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    model.presentImportPanel()
                }
            })
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HUD.textSoft)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(HUD.hairline, lineWidth: 0.8)
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 14)
        }
        .background(HUD.void)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(HUD.void)
    }
}
#endif
