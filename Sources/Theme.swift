import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

enum Theme {
    static let bg = Color(light: UIColor(hex: 0xF5F5F7), dark: UIColor(hex: 0x0A0A0C))
    static let grid = Color(light: UIColor(hex: 0xE11D48, alpha: 0.10), dark: UIColor(hex: 0xFF5470, alpha: 0.09))
    static let card = Color(light: UIColor(hex: 0xE9E9ED), dark: UIColor(hex: 0x17171B))
    static let border = Color(light: UIColor(hex: 0xDCDCE2), dark: UIColor(hex: 0x2A2A30))
    static let text = Color(light: UIColor(hex: 0x0A0A0B), dark: UIColor(hex: 0xF5F5F7))
    static let sub = Color(light: UIColor(hex: 0x5F5F67), dark: UIColor(hex: 0x9A9AA2))
    static let accent = Color(light: UIColor(hex: 0xE11D48), dark: UIColor(hex: 0xFF5470))
    static let button = Color(light: UIColor.white, dark: UIColor(hex: 0x1C1C20))
    static let highlight = Color(light: UIColor(hex: 0x787880, alpha: 0.16), dark: UIColor(white: 1, alpha: 0.10))
    static let track = Color(light: UIColor(hex: 0xD2D2D8), dark: UIColor(hex: 0x2A2A30))
    static let brand = Color(hex: 0xE11D48)

    static let purpleFg = Color(light: UIColor(hex: 0x5B38D1), dark: UIColor(hex: 0xB9A2FF))
    static let purpleBg = Color(light: UIColor(hex: 0x7C5CE0, alpha: 0.16), dark: UIColor(hex: 0x966EFF, alpha: 0.20))
    static let redFg = Color(light: UIColor(hex: 0xC4183A), dark: UIColor(hex: 0xFF7A88))
    static let redBg = Color(light: UIColor(hex: 0xE43456, alpha: 0.14), dark: UIColor(hex: 0xFF455A, alpha: 0.20))
    static let grayFg = Color(light: UIColor(hex: 0x55555D), dark: UIColor(hex: 0xA8A8B0))
    static let grayBg = Color(light: UIColor(hex: 0x787880, alpha: 0.16), dark: UIColor(hex: 0x969AA0, alpha: 0.18))
    static let greenFg = Color(light: UIColor(hex: 0x137A3A), dark: UIColor(hex: 0x5BE08A))
    static let greenBg = Color(light: UIColor(hex: 0x22A050, alpha: 0.16), dark: UIColor(hex: 0x3CC86E, alpha: 0.18))
}

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: Backdrop

struct GridBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            Canvas { ctx, size in
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += 40
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += 40
                }
                ctx.stroke(path, with: .color(Theme.grid), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: Building blocks

struct CardStyle: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

extension View {
    func card(_ radius: CGFloat = 20) -> some View { modifier(CardStyle(radius: radius)) }

    func plainRow(top: CGFloat = 5, bottom: CGFloat = 5) -> some View {
        self.listRowInsets(EdgeInsets(top: top, leading: 20, bottom: bottom, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct PageTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 36, weight: .heavy))
            .tracking(-1)
            .foregroundColor(Theme.text)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.mono(12))
            .tracking(2.5)
            .foregroundColor(Theme.sub)
    }
}

struct CircleIcon: View {
    let symbol: String
    var tint: Color = Theme.text
    var filled: Bool = true

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 44, height: 44)
            .background(Circle().fill(filled ? Theme.button : Color.clear))
            .overlay(Circle().stroke(filled ? Color.clear : Theme.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(filled ? 0.10 : 0), radius: 10, x: 0, y: 4)
            .contentShape(Circle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

enum TagKind { case red, purple, gray, green }

struct Tag: View {
    let text: String
    var icon: String? = nil
    var kind: TagKind = .gray

    private var colors: (Color, Color) {
        switch kind {
        case .red: return (Theme.redFg, Theme.redBg)
        case .purple: return (Theme.purpleFg, Theme.purpleBg)
        case .gray: return (Theme.grayFg, Theme.grayBg)
        case .green: return (Theme.greenFg, Theme.greenBg)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.mono(12))
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundColor(colors.0)
        .background(Capsule().fill(colors.1))
        .animation(.easeOut(duration: 0.25), value: text)
    }
}

struct FileTile: View {
    var symbol: String = "doc.fill"
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xFF4D6D), Color(hex: 0x8B5CF6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
    }
}

struct ProgressBar: View {
    var value: Double
    var active: Bool = true
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let w = max(5, g.size.width * CGFloat(min(max(value, 0), 1)))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(active
                          ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF4D6D), Theme.accent],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Theme.sub))
                    .frame(width: w)
                    .overlay(alignment: .leading) {
                        if active {
                            Capsule()
                                .fill(LinearGradient(colors: [Color.clear, Color.white.opacity(0.5), Color.clear],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: 36)
                                .offset(x: -36 + (w + 36) * phase)
                        }
                    }
                    .clipShape(Capsule())
                    .animation(.easeOut(duration: 0.45), value: w)
            }
        }
        .frame(height: 5)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundColor(Theme.sub)
            Text(title).font(.mono(14, .semibold)).foregroundColor(Theme.text)
            Text(hint).font(.mono(12)).foregroundColor(Theme.sub).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

struct Shake: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 2 * 3), y: 0))
    }
}

// MARK: Helpers

enum Haptic {
    private static var on: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
    static func tap() {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warn() {
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
    static func speed(_ bps: Double) -> String {
        guard bps > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
    }
    static func eta(_ s: Double?) -> String {
        guard let s, s.isFinite, s > 0 else { return "—" }
        if s < 60 { return "\(Int(s)) sec left" }
        if s < 3600 { return "\(Int(s / 60)) min left" }
        return "\(Int(s) / 3600)h \((Int(s) % 3600) / 60)m left"
    }
}
