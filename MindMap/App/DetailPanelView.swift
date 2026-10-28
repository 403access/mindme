import SwiftUI
import MindMapCore
import AppKit

struct DetailPanelView: View {
    @ObservedObject var model: AppModel
    var node: MindMapNode

    @State private var expandedMessages: Set<String> = []

    private var thread: ConversationThread? {
        model.thread(for: node)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(HUD.hairline)
            ScrollView(showsIndicators: false) {
                Group {
                    if let thread {
                        threadContent(thread)
                    } else {
                        clusterContent
                    }
                }
                .padding(16)
            }
            Divider().overlay(HUD.hairline)
            footer
        }
        .hudPanel(cornerRadius: 16)
        .id(node.id)
    }

    // MARK: - Header

    private var headerLabel: String {
        switch node.kind {
        case .thread: return "THREAD INSPECTOR"
        case .tag: return "TAG INSPECTOR"
        case .root: return "NEXUS INSPECTOR"
        case .group:
            if model.grouping == .region {
                return node.parentID == nil ? "REGION INSPECTOR" : "SUB-REGION INSPECTOR"
            }
            return "CLUSTER INSPECTOR"
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(HUD.color(for: node))
                    .frame(width: 2, height: 12)
                    .shadow(color: HUD.color(for: node).opacity(0.8), radius: 4)
                Text(headerLabel)
                    .font(HUDFont.micro(8))
                    .tracking(1.5)
                    .foregroundStyle(HUD.textSoft)
            }
            Spacer()
            HUDIconButton(systemName: "scope", help: "Center on node") {
                model.engine.focus(nodeID: node.id)
            }
            HUDIconButton(systemName: "xmark", help: "Close inspector") {
                model.deselect()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    // MARK: - Thread

    private func threadContent(_ thread: ConversationThread) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    ProviderBadge(provider: thread.provider)
                    if let modelName = thread.model, !modelName.isEmpty {
                        Text(modelName.uppercased())
                            .font(HUDFont.micro(7))
                            .tracking(0.6)
                            .foregroundStyle(HUD.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.035))
                                    .overlay(Capsule().strokeBorder(HUD.hairline, lineWidth: 0.7))
                            )
                    }
                    Spacer(minLength: 0)
                    if thread.isDemo {
                        Text("SYNTHETIC")
                            .font(HUDFont.micro(6.5))
                            .tracking(0.7)
                            .foregroundStyle(HUD.amber.opacity(0.8))
                    }
                }

                Text(thread.title)
                    .font(HUDFont.display(19, weight: .semibold))
                    .foregroundStyle(HUD.text)
                    .lineSpacing(2)
                    .textSelection(.enabled)

                HStack(spacing: 7) {
                    Text(Format.dayRange(thread.dateRange))
                        .font(HUDFont.micro(7.5))
                        .tracking(0.5)
                        .foregroundStyle(HUD.muted)
                    Text("·")
                        .foregroundStyle(HUD.dim)
                    Text(Format.count(thread.messageCount, "MESSAGE", "MESSAGES"))
                        .font(HUDFont.micro(7.5))
                        .tracking(0.5)
                        .foregroundStyle(HUD.muted)
                    Text("·")
                        .foregroundStyle(HUD.dim)
                    Text(Format.compactCount(thread.characterCount) + " CHARS")
                        .font(HUDFont.micro(7.5))
                        .tracking(0.5)
                        .foregroundStyle(HUD.muted)
                }

                if !model.selectedThreadTags.isEmpty {
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(model.selectedThreadTags, id: \.self) { tag in
                            TagChip(text: tag) {
                                let tagID = "tag:\(TextTools.slug(tag))"
                                if model.graph.node(id: tagID) != nil {
                                    model.select(tagID, focus: true)
                                } else {
                                    model.searchText = tag
                                }
                            }
                        }
                    }
                    .padding(.top, 1)
                }
            }

            statsGrid(thread)

            if model.showSpend, thread.hasCostData {
                spendStrip(
                    cost: thread.totalCost,
                    tokens: thread.tokenCount,
                    detail: "\(Format.cost(thread.costPerMessage)) / MESSAGE"
                )
            }

            if let profile = model.topicProfile(for: thread.id), !profile.segments.isEmpty {
                regionSection(profile)
            }

            Divider().overlay(HUD.hairline)

            HStack(spacing: 8) {
                MicroLabel(text: "Transcript", color: HUD.textSoft)
                Text("\(thread.messages.count)")
                    .font(HUDFont.micro(7.5))
                    .foregroundStyle(HUD.accent.opacity(0.8))
                Rectangle().fill(HUD.hairline).frame(height: 1)
                Text("READ ONLY")
                    .font(HUDFont.micro(6.5))
                    .tracking(0.8)
                    .foregroundStyle(HUD.dim)
            }

            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(thread.messages.enumerated()), id: \.element.id) { index, message in
                    MessageRow(
                        message: message,
                        index: index,
                        isExpanded: expandedMessages.contains(message.id),
                        toggleExpand: {
                            if expandedMessages.contains(message.id) {
                                expandedMessages.remove(message.id)
                            } else {
                                expandedMessages.insert(message.id)
                            }
                        }
                    )
                }
            }
        }
    }

    private func spendStrip(cost: Double, tokens: Int, detail: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                MicroLabel(text: "Spend", color: HUD.textSoft)
                Text(Format.cost(cost))
                    .font(HUDFont.label(15))
                    .foregroundStyle(HUD.amber)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                if tokens > 0 {
                    Text("\(Format.compactCount(tokens)) TOKENS")
                        .font(HUDFont.micro(6.5))
                        .tracking(0.6)
                        .foregroundStyle(HUD.textSoft)
                }
                Text(detail)
                    .font(HUDFont.micro(6.5))
                    .tracking(0.6)
                    .foregroundStyle(HUD.dim)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(HUD.amber.opacity(0.045))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUD.amber.opacity(0.22), lineWidth: 0.8))
        )
    }

    private func regionSection(_ profile: ThreadTopicProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                MicroLabel(text: "Regions", color: HUD.textSoft)
                Text("\(profile.segments.count) SEGMENTS")
                    .font(HUDFont.micro(6.5))
                    .tracking(0.8)
                    .foregroundStyle(HUD.dim)
                Spacer(minLength: 0)
                Text("ON-DEVICE")
                    .font(HUDFont.micro(6))
                    .tracking(0.7)
                    .foregroundStyle(HUD.dim)
            }

            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(profile.regions.prefix(4)) { share in
                    Text(
                        model.showSpend && share.cost > 0
                            ? "\(share.label.uppercased()) \(share.percentage)% · \(Format.cost(share.cost))"
                            : "\(share.label.uppercased()) \(share.percentage)%"
                    )
                    .font(HUDFont.micro(6.5))
                        .tracking(0.5)
                        .foregroundStyle(HUD.textSoft)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(HUD.accent.opacity(0.07))
                                .overlay(Capsule().strokeBorder(HUD.accent.opacity(0.22), lineWidth: 0.7))
                        )
                }
            }

            VStack(spacing: 1) {
                ForEach(profile.segments.prefix(5)) { segment in
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(HUD.accent.opacity(0.55))
                            .frame(width: 2, height: 9)
                        Text(segment.displayTitle)
                            .font(HUDFont.micro(7))
                            .foregroundStyle(HUD.textSoft)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(segment.startMessageIndex + 1)–\(segment.endMessageIndex)")
                            .font(HUDFont.micro(6.5))
                            .foregroundStyle(HUD.dim)
                        if model.showSpend, segment.cost > 0 {
                            Text(Format.cost(segment.cost))
                                .font(HUDFont.micro(6.5))
                                .foregroundStyle(HUD.amber)
                        }
                        Text("\(Int((segment.confidence * 100).rounded()))%")
                            .font(HUDFont.micro(6.5))
                            .foregroundStyle(HUD.dim)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.02))
                    )
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUD.hairline, lineWidth: 0.8))
        )
    }

    private func statsGrid(_ thread: ConversationThread) -> some View {
        HStack(spacing: 0) {
            statCell(value: "\(thread.userMessageCount)", label: "PROMPTS")
            statDivider
            statCell(value: "\(thread.messageCount)", label: "MESSAGES")
            statDivider
            statCell(value: Format.compactCount(thread.wordCount), label: "WORDS")
        }
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUD.hairline, lineWidth: 0.8))
        )
    }

    private var statDivider: some View {
        Rectangle().fill(HUD.hairline).frame(width: 1, height: 20)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(HUDFont.label(12))
                .foregroundStyle(HUD.text)
            Text(label)
                .font(HUDFont.micro(6.5))
                .tracking(0.8)
                .foregroundStyle(HUD.dim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cluster / overview

    private var clusterBadge: String {
        if node.kind == .tag { return "SHARED TAG" }
        if node.kind == .root { return "NEXUS OVERVIEW" }
        if model.grouping == .region {
            return node.parentID == nil ? "REGION" : "SUB-REGION"
        }
        return "CONSTELLATION"
    }

    private var clusterContent: some View {
        let threads = model.threads(for: node)
        let accent = HUD.color(for: node)
        return VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let provider = node.provider {
                        ProviderBadge(provider: provider)
                    } else {
                        Text(clusterBadge)
                            .font(HUDFont.micro(7.5))
                            .tracking(1.1)
                            .foregroundStyle(accent)
                    }
                    Spacer()
                    Text(Format.count(threads.count, "THREAD", "THREADS"))
                        .font(HUDFont.micro(7))
                        .tracking(0.8)
                        .foregroundStyle(HUD.muted)
                }

                Text(node.kind == .tag ? "#\(node.label)" : node.label.uppercased())
                    .font(HUDFont.display(21, weight: .semibold))
                    .tracking(node.kind == .tag ? 0 : 0.6)
                    .foregroundStyle(HUD.text)

                Text(clusterDescription(node))
                    .font(HUDFont.body(11.5))
                    .foregroundStyle(HUD.muted)
                    .lineSpacing(3)
            }

            if node.kind == .group, model.grouping == .region {
                let children = model.graph.childGroups(of: node.id)
                if !children.isEmpty {
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(children) { child in
                            Button {
                                model.select(child.id, focus: true)
                            } label: {
                                let count = model.graph.threadNodes.filter { $0.groupID == child.id }.count
                                Text("\(child.label) \(count)")
                                    .font(HUDFont.micro(6.5))
                                    .tracking(0.5)
                                    .foregroundStyle(HUD.textSoft)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.035))
                                            .overlay(Capsule().strokeBorder(HUD.hairline, lineWidth: 0.7))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 0) {
                statCell(value: "\(threads.count)", label: "THREADS")
                statDivider
                statCell(value: Format.compactCount(threads.reduce(0) { $0 + $1.messageCount }), label: "MESSAGES")
                statDivider
                statCell(value: Format.compactCount(threads.reduce(0) { $0 + $1.characterCount }), label: "CHARS")
            }
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUD.hairline, lineWidth: 0.8))
            )

            if model.showSpend, node.cost > 0 {
                let costed = threads.filter(\.hasCostData).count
                spendStrip(
                    cost: node.cost,
                    tokens: node.tokenCount,
                    detail: "\(costed) OF \(threads.count) THREADS COSTED"
                )
            }

            HStack(spacing: 8) {
                MicroLabel(text: node.kind == .root ? "Recent signal" : "Connected threads", color: HUD.textSoft)
                Rectangle().fill(HUD.hairline).frame(height: 1)
            }

            VStack(spacing: 1) {
                ForEach(threads.prefix(30)) { thread in
                    Button {
                        model.select(threadID: thread.id)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(HUD.providerColor(thread.provider))
                                .frame(width: 4.5, height: 4.5)
                                .shadow(color: HUD.providerColor(thread.provider).opacity(0.8), radius: 3)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(thread.title)
                                    .font(HUDFont.body(11.5))
                                    .foregroundStyle(HUD.textSoft)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                HStack(spacing: 5) {
                                    Text(thread.provider.displayName.uppercased())
                                        .font(HUDFont.micro(6.5))
                                        .tracking(0.5)
                                        .foregroundStyle(HUD.providerColor(thread.provider).opacity(0.7))
                                    Text("·")
                                        .foregroundStyle(HUD.dim)
                                    Text("\(thread.messageCount) MSG")
                                        .font(HUDFont.micro(6.5))
                                        .foregroundStyle(HUD.dim)
                                    Text("·")
                                        .foregroundStyle(HUD.dim)
                                    Text(Format.relative(thread.updatedAt).uppercased())
                                        .font(HUDFont.micro(6.5))
                                        .foregroundStyle(HUD.dim)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(HUD.dim.opacity(0.6))
                                .padding(.top, 5)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.012))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if threads.count > 30 {
                Text("+ \(threads.count - 30) MORE THREADS IN THIS CLUSTER")
                    .font(HUDFont.micro(6.8))
                    .tracking(0.8)
                    .foregroundStyle(HUD.dim)
                    .padding(.leading, 2)
            }
        }
    }

    private func clusterDescription(_ node: MindMapNode) -> String {
        switch node.kind {
        case .root:
            return "Every imported conversation, connected through shared language. \(model.library.threads.count) threads from \(activeProviderCount) sources."
        case .group:
            if let provider = node.provider {
                return "Conversations ingested from \(provider.displayName). Toggle the source in the filter matrix to isolate it."
            }
            if node.id.contains("topic") {
                return "A topic constellation assembled from keywords shared across conversations. Threads can connect to several tags."
            }
            return "A temporal shell grouping conversations by the period in which they were last active."
        case .tag:
            return "Threads that independently surfaced “\(node.label)” as a defining keyword. The connection crosses providers."
        case .thread:
            return ""
        }
    }

    private var activeProviderCount: Int {
        Provider.allCases.filter { model.providerCount($0) > 0 }.count
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 7) {
            HUDGhostButton(title: "Center", icon: "scope") {
                model.engine.focus(nodeID: node.id, zoom: model.engine.frame.camera.zoom)
            }
            if let thread, let link = thread.deepLink, !thread.isDemo {
                Button {
                    NSWorkspace.shared.open(link)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("OPEN SOURCE")
                            .font(HUDFont.micro(8))
                            .tracking(0.8)
                    }
                    .foregroundStyle(HUD.accent)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(HUD.accent.opacity(0.09))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUD.accent.opacity(0.4), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                model.deselect()
            } label: {
                Text("CLOSE")
                    .font(HUDFont.micro(8))
                    .tracking(1)
                    .foregroundStyle(HUD.muted)
                    .padding(.horizontal, 6)
                    .frame(height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(HUD.deep.opacity(0.98))
    }
}

// MARK: - Message row

struct MessageRow: View {
    var message: ChatMessage
    var index: Int
    var isExpanded: Bool
    var toggleExpand: () -> Void

    private var tint: Color {
        switch message.role {
        case .user: return HUD.accent
        case .assistant: return HUD.providerColor(.chatgpt).opacity(0.55)
        case .system: return HUD.amber.opacity(0.5)
        case .tool: return HUD.magenta.opacity(0.5)
        }
    }

    private var needsExpand: Bool { message.text.count > 520 }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(roleLabel)
                    .font(HUDFont.micro(6.8))
                    .tracking(0.9)
                    .foregroundStyle(tint)
                if let timestamp = message.timestamp {
                    Text(Format.clock.string(from: timestamp))
                        .font(HUDFont.micro(6.5))
                        .foregroundStyle(HUD.dim)
                }
                Text(String(format: "%02d", index + 1))
                    .font(HUDFont.micro(6.5))
                    .foregroundStyle(HUD.dim.opacity(0.6))
            }
            .frame(width: 48, alignment: .leading)
            .padding(.top, 2)

            Rectangle()
                .fill(tint.opacity(0.35))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(message.text)
                    .font(HUDFont.body(11.8))
                    .foregroundStyle(message.role == .system ? HUD.muted : HUD.text.opacity(0.9))
                    .lineSpacing(3.2)
                    .textSelection(.enabled)
                    .lineLimit(isExpanded ? nil : (needsExpand ? 14 : nil))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if needsExpand {
                    Button(action: toggleExpand) {
                        Text(isExpanded ? "COLLAPSE" : "EXPAND FULL MESSAGE")
                            .font(HUDFont.micro(6.8))
                            .tracking(0.8)
                            .foregroundStyle(HUD.accent.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "YOU"
        case .assistant: return "MODEL"
        case .system: return "SYSTEM"
        case .tool: return "TOOL"
        }
    }
}

// MARK: - Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [(height: CGFloat, width: CGFloat, count: Int)] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        var currentCount = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = size.width + (currentCount > 0 ? spacing : 0)
            if currentWidth + needed > maxWidth, currentCount > 0 {
                rows.append((currentHeight, currentWidth, currentCount))
                currentWidth = size.width
                currentHeight = size.height
                currentCount = 1
            } else {
                currentWidth += needed
                currentHeight = max(currentHeight, size.height)
                currentCount += 1
            }
        }
        if currentCount > 0 {
            rows.append((currentHeight, currentWidth, currentCount))
        }

        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
