import SwiftUI
import MindMapCore

// MARK: - Palette

enum HUD {
    static let void = Color(hex: 0x04060B)
    static let deep = Color(hex: 0x070B14)
    static let panel = Color(hex: 0x0A111C)
    static let panelRaised = Color(hex: 0x0D1522)
    static let accent = Color(hex: 0x5FE3FF)
    static let accentSoft = Color(hex: 0x5FE3FF).opacity(0.16)
    static let magenta = Color(hex: 0xFF5FD2)
    static let lime = Color(hex: 0xB6FF6B)
    static let amber = Color(hex: 0xFFC46B)
    static let text = Color(hex: 0xE9F1FF)
    static let textSoft = Color(hex: 0xA9B6CC)
    static let muted = Color(hex: 0x71809A)
    static let dim = Color(hex: 0x3D485C)
    static let hairline = Color.white.opacity(0.08)

    static func providerColor(_ provider: Provider) -> Color {
        switch provider {
        case .chatgpt: return Color(hex: 0x4FF0B4)
        case .gemini: return Color(hex: 0x7C9CFF)
        case .claude: return Color(hex: 0xFF9A6B)
        case .opencode: return Color(hex: 0xFFD166)
        case .other: return Color(hex: 0xC9B6FF)
        }
    }

    static let topicPalette: [Color] = [
        Color(hex: 0x5FE3FF),
        Color(hex: 0xFF6BCB),
        Color(hex: 0xB8FF6B),
        Color(hex: 0xFFC46B),
        Color(hex: 0x9D8CFF),
        Color(hex: 0x5CFFD8),
        Color(hex: 0xFF8FA3),
        Color(hex: 0x6BA8FF),
        Color(hex: 0xE8D66B),
        Color(hex: 0xD59CFF)
    ]

    static func topicColor(seed: Int) -> Color {
        topicPalette[abs(seed) % topicPalette.count]
    }

    static func color(for node: MindMapNode) -> Color {
        switch node.kind {
        case .root: return accent
        case .group:
            if let provider = node.provider { return HUD.providerColor(provider) }
            return topicColor(seed: node.colorSeed)
        case .thread:
            if let provider = node.provider { return HUD.providerColor(provider) }
            return topicColor(seed: node.colorSeed)
        case .tag:
            return Color(hex: 0xAFC3FF)
        }
    }
}

// MARK: - Type

enum HUDFont {
    static func micro(_ size: CGFloat = 8.5) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    static func label(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    static func display(_ size: CGFloat = 18, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func body(_ size: CGFloat = 12.5) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
}

// MARK: - Panel chrome

struct HUDPanel: ViewModifier {
    var cornerRadius: CGFloat = 16
    var accent: Color = HUD.accent
    var showsBrackets: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [HUD.panel.opacity(0.94), HUD.deep.opacity(0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.03), accent.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay {
                if showsBrackets {
                    CornerTicks(inset: 7, length: 13)
                        .stroke(accent.opacity(0.42), style: StrokeStyle(lineWidth: 1, lineCap: .square))
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 26, x: 0, y: 14)
    }
}

extension View {
    func hudPanel(cornerRadius: CGFloat = 16, accent: Color = HUD.accent, brackets: Bool = true) -> some View {
        modifier(HUDPanel(cornerRadius: cornerRadius, accent: accent, showsBrackets: brackets))
    }
}

struct CornerTicks: Shape {
    var inset: CGFloat = 8
    var length: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX = rect.minX + inset
        let maxX = rect.maxX - inset
        let minY = rect.minY + inset
        let maxY = rect.maxY - inset

        path.move(to: CGPoint(x: minX, y: minY + length))
        path.addLine(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: minX + length, y: minY))

        path.move(to: CGPoint(x: maxX - length, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY + length))

        path.move(to: CGPoint(x: minX, y: maxY - length))
        path.addLine(to: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: minX + length, y: maxY))

        path.move(to: CGPoint(x: maxX - length, y: maxY))
        path.addLine(to: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - length))

        return path
    }
}

// MARK: - Small building blocks

struct MicroLabel: View {
    var text: String
    var color: Color = HUD.muted
    var size: CGFloat = 8.5

    var body: some View {
        Text(text.uppercased())
            .font(HUDFont.micro(size))
            .tracking(1.25)
            .foregroundStyle(color)
    }
}

struct SectionHeader: View {
    var index: String
    var title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(index)
                .font(HUDFont.micro(8))
                .tracking(1)
                .foregroundStyle(HUD.accent.opacity(0.65))
            Text(title.uppercased())
                .font(HUDFont.label(9))
                .tracking(1.6)
                .foregroundStyle(HUD.textSoft)
            Rectangle()
                .fill(HUD.hairline)
                .frame(height: 1)
            if let trailing {
                Text(trailing.uppercased())
                    .font(HUDFont.micro(8))
                    .tracking(0.8)
                    .foregroundStyle(HUD.muted)
            }
        }
    }
}

struct StatusDot: View {
    var color: Color = HUD.lime
    var size: CGFloat = 5
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: pulse ? 5 : 1)
            .scaleEffect(pulse ? 1.15 : 0.9)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

struct ProviderBadge: View {
    var provider: Provider
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(HUD.providerColor(provider))
                .frame(width: 5, height: 5)
                .shadow(color: HUD.providerColor(provider).opacity(0.8), radius: 3)
            Text(provider.displayName.uppercased())
                .font(HUDFont.micro(compact ? 8 : 8.5))
                .tracking(1.1)
                .foregroundStyle(HUD.providerColor(provider))
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(
            Capsule()
                .fill(HUD.providerColor(provider).opacity(0.10))
                .overlay(Capsule().strokeBorder(HUD.providerColor(provider).opacity(0.35), lineWidth: 0.8))
        )
    }
}

struct TagChip: View {
    var text: String
    var active: Bool = false
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            Text(text.uppercased())
                .font(HUDFont.micro(8))
                .tracking(0.8)
                .foregroundStyle(active ? HUD.accent : HUD.textSoft)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(active ? HUD.accent.opacity(0.12) : Color.white.opacity(0.035))
                        .overlay(Capsule().strokeBorder(active ? HUD.accent.opacity(0.5) : HUD.hairline, lineWidth: 0.8))
                )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - Buttons

struct HUDIconButton: View {
    var systemName: String
    var help: String
    var active: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(active || hovering ? HUD.accent : HUD.textSoft)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? HUD.accent.opacity(0.12) : (hovering ? Color.white.opacity(0.06) : Color.white.opacity(0.02)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(active ? HUD.accent.opacity(0.4) : HUD.hairline, lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct HUDPrimaryButton: View {
    var title: String
    var icon: String?
    var tint: Color = HUD.accent
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: .bold))
                }
                Text(title.uppercased())
                    .font(HUDFont.label(9.5))
                    .tracking(1.1)
            }
            .foregroundStyle(Color(hex: 0x05101A))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: hovering ? [tint, tint.opacity(0.72)] : [tint.opacity(0.92), tint.opacity(0.62)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
            )
            .shadow(color: tint.opacity(hovering ? 0.45 : 0.22), radius: hovering ? 14 : 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct HUDGhostButton: View {
    var title: String
    var icon: String?
    var tint: Color = HUD.textSoft
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 9.5, weight: .semibold))
                }
                Text(title.uppercased())
                    .font(HUDFont.micro(8.5))
                    .tracking(0.9)
            }
            .foregroundStyle(hovering ? tint : tint.opacity(0.75))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.06) : Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(hovering ? tint.opacity(0.35) : HUD.hairline, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct NeonToggle: View {
    var isOn: Bool
    var color: Color = HUD.accent

    var body: some View {
        Capsule()
            .fill(isOn ? color.opacity(0.18) : Color.white.opacity(0.03))
            .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.65) : HUD.dim.opacity(0.7), lineWidth: 0.8))
            .frame(width: 28, height: 15)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? color : HUD.dim)
                    .frame(width: 9, height: 9)
                    .shadow(color: isOn ? color.opacity(0.8) : .clear, radius: 4)
                    .padding(3)
            }
            .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}

// MARK: - Formatting

enum Format {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM yyyy"
        return f
    }()

    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    static func compactCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }

    static func relative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3_600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h ago" }
        if interval < 86_400 * 30 { return "\(Int(interval / 86_400))d ago" }
        if interval < 86_400 * 365 { return "\(Int(interval / (86_400 * 30)))mo ago" }
        return "\(Int(interval / (86_400 * 365)))y ago"
    }

    static func dayRange(_ range: ClosedRange<Date>?) -> String {
        guard let range else { return "—" }
        if Calendar.current.isDate(range.lowerBound, inSameDayAs: range.upperBound) {
            return shortDate.string(from: range.lowerBound)
        }
        return "\(shortDate.string(from: range.lowerBound)) → \(shortDate.string(from: range.upperBound))"
    }
}

// MARK: - Color

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
