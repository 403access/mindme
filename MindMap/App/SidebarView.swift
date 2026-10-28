import SwiftUI
import MindMapCore

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(HUD.hairline)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    sourcesSection
                    groupingSection
                    timeSection
                    querySection
                    signalSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }

            Divider().overlay(HUD.hairline)
            footer
        }
        .hudPanel(cornerRadius: 16)
        .onChange(of: model.searchFocusRequest) { _, _ in
            searchFocused = true
        }
        .onAppear {
            // macOS focuses the first text field on launch; keep the map itself
            // in focus until the user actually asks to search.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                searchFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text("FILTER MATRIX")
                    .font(HUDFont.label(10))
                    .tracking(2.2)
                    .foregroundStyle(HUD.text)
                Text("SIGNAL / LENS / WINDOW")
                    .font(HUDFont.micro(7))
                    .tracking(0.9)
                    .foregroundStyle(HUD.dim)
            }
            Spacer()
            Button {
                model.resetFilters()
                model.engine.requestFit()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(HUD.muted)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(HUD.hairline, lineWidth: 0.8))
                    )
            }
            .buttonStyle(.plain)
            .help("Reset filters")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(index: "01", title: "Sources", trailing: activeSourceCount)

            VStack(spacing: 5) {
                ForEach(Provider.allCases, id: \.self) { provider in
                    sourceRow(provider)
                }
            }
        }
    }

    private var activeSourceCount: String {
        let active = Provider.allCases.filter { model.providers.contains($0) && model.providerCount($0) > 0 }
        return "\(active.count)/\(Provider.allCases.filter { model.providerCount($0) > 0 }.count)"
    }

    private func sourceRow(_ provider: Provider) -> some View {
        let count = model.providerCount(provider)
        let isScan = provider == .opencode && count == 0
        let enabled = model.providers.contains(provider)
        let available = count > 0 || isScan
        let accent = HUD.providerColor(provider)
        let interactive = enabled && available

        return Button {
            guard available else { return }
            if isScan {
                model.importOpenCodeSessions()
            } else {
                model.toggleProvider(provider)
            }
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(interactive ? 0.16 : 0.05))
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(accent.opacity(available ? 0.95 : 0.3))
                        .frame(width: 4.5, height: 4.5)
                        .shadow(color: accent.opacity(available ? 0.9 : 0), radius: 4)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(HUDFont.body(11.5))
                        .foregroundStyle(available ? (interactive ? HUD.text : HUD.muted) : HUD.dim)
                    Text(rowSubtitle(provider: provider, count: count, isScan: isScan))
                        .font(HUDFont.micro(7))
                        .tracking(0.7)
                        .foregroundStyle(isScan ? accent.opacity(0.8) : HUD.dim)
                }
                Spacer(minLength: 4)
                if isScan {
                    HStack(spacing: 4) {
                        if model.isImporting {
                            ProgressView().controlSize(.small).scaleEffect(0.55)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 10, weight: .medium))
                        }
                        Text("SCAN")
                            .font(HUDFont.micro(7))
                            .tracking(0.7)
                    }
                    .foregroundStyle(accent.opacity(0.85))
                } else {
                    NeonToggle(isOn: enabled && available, color: accent)
                        .opacity(available ? 1 : 0.35)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(interactive ? accent.opacity(0.045) : Color.white.opacity(0.015))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                isScan ? accent.opacity(0.28) : (interactive ? accent.opacity(0.18) : HUD.hairline),
                                lineWidth: 0.8
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available || (isScan && model.isImporting))
        .help(
            isScan
                ? "Scan the local OpenCode library (~/.local/share/opencode/opencode.db)"
                : (available ? "Toggle \(provider.displayName)" : "No \(provider.displayName) threads imported")
        )
    }

    private func rowSubtitle(provider: Provider, count: Int, isScan: Bool) -> String {
        if isScan {
            return model.isImporting ? "READING SESSIONS…" : "SCAN LOCAL SESSIONS"
        }
        return count > 0 ? Format.count(count, "THREAD", "THREADS") : "NO DATA"
    }

    // MARK: - Grouping

    private var groupingSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(index: "02", title: "Lens")
            HStack(spacing: 3) {
                ForEach(GroupingMode.allCases) { mode in
                    Button {
                        model.grouping = mode
                    } label: {
                        Text(mode.label)
                            .font(HUDFont.micro(7.5))
                            .tracking(0.9)
                            .foregroundStyle(model.grouping == mode ? Color(hex: 0x05101A) : HUD.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(model.grouping == mode ? HUD.accent.opacity(0.9) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HUD.hairline, lineWidth: 0.8))
            )
        }
    }

    // MARK: - Time

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(index: "03", title: "Window")
            HStack(spacing: 4) {
                ForEach(TimeWindow.allCases) { window in
                    Button {
                        model.timeWindow = window
                    } label: {
                        Text(window.label)
                            .font(HUDFont.micro(7.5))
                            .tracking(0.7)
                            .foregroundStyle(model.timeWindow == window ? HUD.accent : HUD.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(model.timeWindow == window ? HUD.accent.opacity(0.10) : Color.white.opacity(0.015))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(
                                                model.timeWindow == window ? HUD.accent.opacity(0.45) : HUD.hairline,
                                                lineWidth: 0.7
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Query

    private var querySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(
                index: "04",
                title: "Query",
                trailing: model.searchText.isEmpty ? nil : "\(model.visibleThreads.count) HITS"
            )

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(searchFocused ? HUD.accent : HUD.dim)
                Text("FIND")
                    .font(HUDFont.micro(7))
                    .tracking(1)
                    .foregroundStyle(HUD.dim.opacity(0.9))
                ZStack(alignment: .leading) {
                    if model.searchText.isEmpty && !searchFocused {
                        Text("THREADS")
                            .font(HUDFont.micro(9))
                            .tracking(0.7)
                            .foregroundStyle(HUD.muted.opacity(0.55))
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $model.searchText)
                        .textFieldStyle(.plain)
                        .font(HUDFont.micro(9))
                        .tracking(0.7)
                        .foregroundStyle(HUD.text)
                        .focused($searchFocused)
                        .onSubmit { searchFocused = false }
                }
                if !model.searchText.isEmpty {
                    Button {
                        model.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(HUD.dim)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("⌘F")
                        .font(HUDFont.micro(7))
                        .foregroundStyle(HUD.dim)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: 0x050A12).opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(searchFocused ? HUD.accent.opacity(0.45) : HUD.hairline, lineWidth: 0.8)
                    )
            )

            if !model.visibleThreads.isEmpty {
                VStack(spacing: 2) {
                    ForEach(model.visibleThreads.prefix(5)) { thread in
                        resultRow(thread)
                    }
                }
                if model.visibleThreads.count > 5 {
                    Text("+ \(model.visibleThreads.count - 5) MORE IN MAP")
                        .font(HUDFont.micro(7))
                        .tracking(0.8)
                        .foregroundStyle(HUD.dim)
                        .padding(.leading, 2)
                }
            } else if !model.searchText.isEmpty {
                Text("NO MATCHING THREADS")
                    .font(HUDFont.micro(7.5))
                    .tracking(0.9)
                    .foregroundStyle(HUD.dim)
                    .padding(.leading, 2)
            }
        }
    }

    private func resultRow(_ thread: ConversationThread) -> some View {
        let selected = model.selectedNodeID == model.graph.node(forThread: thread.id)?.id
        return Button {
            model.select(threadID: thread.id, focus: true)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(HUD.providerColor(thread.provider))
                    .frame(width: 4, height: 4)
                    .shadow(color: HUD.providerColor(thread.provider).opacity(0.8), radius: 2)
                Text(thread.title)
                    .font(HUDFont.body(10.5))
                    .foregroundStyle(selected ? HUD.text : HUD.textSoft)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(Format.relative(thread.updatedAt).uppercased())
                    .font(HUDFont.micro(6.5))
                    .foregroundStyle(HUD.dim)
            }
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? HUD.accent.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Signal

    private var signalSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(index: "05", title: "Signal")

            ViewModeControl(selection: $model.viewMode)

            HStack(spacing: 5) {
                signalToggle("TAGS", icon: "diamond", isOn: model.showTags) {
                    model.showTags.toggle()
                }
                signalToggle("LABELS", icon: "textformat", isOn: model.showLabels) {
                    model.showLabels.toggle()
                }
                signalToggle("MOTION", icon: "waveform.path", isOn: model.motionEnabled) {
                    model.motionEnabled.toggle()
                }
            }
        }
    }

    private func signalToggle(_ title: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(HUDFont.micro(6.8))
                    .tracking(0.8)
            }
            .foregroundStyle(isOn ? HUD.accent : HUD.dim)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? HUD.accent.opacity(0.07) : Color.white.opacity(0.015))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isOn ? HUD.accent.opacity(0.35) : HUD.hairline, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 9) {
            HUDPrimaryButton(
                title: model.isImporting ? "Parsing…" : "Import exports",
                icon: "square.and.arrow.down"
            ) {
                model.presentImportPanel()
            }
            .disabled(model.isImporting)

            HStack(spacing: 6) {
                if model.library.hasDemoData {
                    Button {
                        model.clearDemoData()
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(HUD.amber).frame(width: 3.5, height: 3.5)
                            Text("DEMO · \(Format.count(model.library.demoThreadCount, "THREAD", "THREADS"))")
                                .font(HUDFont.micro(6.5))
                                .tracking(0.6)
                                .foregroundStyle(HUD.amber.opacity(0.8))
                            Text("CLEAR")
                                .font(HUDFont.micro(6.5))
                                .tracking(0.6)
                                .foregroundStyle(HUD.textSoft)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 6.5))
                        Text("DATA STAYS ON THIS MAC")
                            .font(HUDFont.micro(6.5))
                            .tracking(0.6)
                    }
                    .foregroundStyle(HUD.muted.opacity(0.7))
                }
                Spacer(minLength: 0)
                if let date = model.lastImportDate {
                    Text(Format.relative(date).uppercased())
                        .font(HUDFont.micro(6.5))
                        .foregroundStyle(HUD.dim)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
