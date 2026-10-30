import SwiftUI
import AppKit

// OltraFlim design tokens.
//
// The surface scale follows the high-end dark UI rules: adjacent surfaces move
// by only 1–3% luminance, separation comes from light not from black borders,
// and type weight is dropped one step to compensate for optical irradiation.
enum DS {
    // Surfaces
    static let surface0 = Color(hex: 0x0B0B0B)
    static let surface1 = Color(hex: 0x151515)
    static let surface2 = Color(hex: 0x1A1A19)
    static let surface3 = Color(hex: 0x20201F)
    static let surface4 = Color(hex: 0x262624)

    // Type
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.42)
    static let textQuaternary = Color.white.opacity(0.26)

    // Lines
    static let hairline = Color.white.opacity(0.045)
    static let hairlineStrong = Color.white.opacity(0.09)

    // One restrained accent: brass, borrowed from film sprocket and safelight.
    static let accent = Color(hex: 0xC8A97E)
    static let accentStrong = Color(hex: 0xD9BD95)
    static let accentDim = Color(hex: 0x8E7756)
    static let danger = Color(hex: 0xC7705D)

    // Radius
    static let rSmall: CGFloat = 7
    static let rMedium: CGFloat = 11
    static let rLarge: CGFloat = 15

    // Motion
    /// Global switches driven by the in-app settings panel.
    static var reduceMotion = false
    static var textScale: CGFloat = 1

    static var easeOutExpo: Animation {
        reduceMotion ? .linear(duration: 0.001) : .timingCurve(0.16, 1, 0.3, 1, duration: 0.28)
    }
    static var easeQuick: Animation {
        reduceMotion ? .linear(duration: 0.001) : .timingCurve(0.16, 1, 0.3, 1, duration: 0.18)
    }
    static var spring: Animation {
        reduceMotion ? .linear(duration: 0.001) : .spring(response: 0.32, dampingFraction: 0.72)
    }
    static var snappy: Animation {
        reduceMotion ? .linear(duration: 0.001) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    // Type scale
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * textScale, weight: weight)
    }
    static func label(_ size: CGFloat = 11) -> Font { .system(size: size * textScale, weight: .regular) }
    static func medium(_ size: CGFloat = 11) -> Font { .system(size: size * textScale, weight: .medium) }
    static func strong(_ size: CGFloat = 12) -> Font { .system(size: size * textScale, weight: .semibold) }
    static func title(_ size: CGFloat = 20) -> Font { .system(size: size * textScale, weight: .medium) }
    static func mono(_ size: CGFloat = 11, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * textScale, weight: weight, design: .monospaced)
    }
}

// MARK: - Brand mark

enum AppLogo {
    /// The film-strip "Q" mark, shipped as a transparent PNG and reused
    /// everywhere the app shows its identity.
    static let mark: NSImage? = NSImage(contentsOf: ResourceLocator.resourceURL("LogoMark.png"))
}

extension Color {
    init?(hexString: String) {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(hex: value)
    }

    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension View {
    func hairlineBorder(_ radius: CGFloat, opacity: Double = 1.0) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(DS.hairline.opacity(opacity), lineWidth: 1)
        )
    }

    func inspectorSectionSpacing() -> some View {
        padding(.horizontal, 18)
    }

    /// Window-level configuration that SwiftUI cannot express directly.
    func configureWindow() -> some View {
        background(WindowConfigurator().frame(width: 0, height: 0))
    }
}

// MARK: - Interaction primitives

struct HoverSurface: ViewModifier {
    @State private var hovering = false
    var enabled: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous)
                    .fill(hovering && enabled ? DS.surface2 : .clear)
            )
            .onHover { value in
                guard enabled else { return }
                withAnimation(DS.easeQuick) { hovering = value }
            }
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.985
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(DS.easeQuick, value: configuration.isPressed)
    }
}

