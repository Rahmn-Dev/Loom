import SwiftUI
import AppKit

enum LoomTheme {
    static let background = Color(red: 0.025, green: 0.045, blue: 0.14)
    static let panel = Color.white.opacity(0.055)
    static let stroke = Color.white.opacity(0.11)
    static let primary = Color(red: 0.42, green: 0.52, blue: 1)
    static let cyan = Color(red: 0.32, green: 0.83, blue: 1)
    static let green = Color(red: 0.23, green: 0.89, blue: 0.50)
    static let secondaryText = Color(red: 0.67, green: 0.72, blue: 0.88)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LoomTheme.background
            RadialGradient(colors: [Color.blue.opacity(0.42), .clear], center: .topTrailing,
                           startRadius: 0, endRadius: 760)
            RadialGradient(colors: [Color.purple.opacity(0.34), .clear], center: .bottomLeading,
                           startRadius: 0, endRadius: 640)
            LinearGradient(colors: [Color.purple.opacity(0.15), .clear, Color.cyan.opacity(0.09)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LoomTheme.panel)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(LoomTheme.stroke, lineWidth: 1))
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = 18) -> some View { modifier(GlassCardModifier(radius: radius)) }
}

/// Consistent pointer and press feedback for Loom's custom, plain-style controls.
/// Native bordered controls, toggles, pickers, and text fields retain AppKit's own hover behavior.
struct LoomHoverButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12
    var fillOpacity: Double = 0.09
    var hoverScale: CGFloat = 1.012

    func makeBody(configuration: Configuration) -> some View {
        LoomHoverButtonBody(configuration: configuration, cornerRadius: cornerRadius,
                            fillOpacity: fillOpacity, hoverScale: hoverScale)
    }
}

private struct LoomHoverButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let cornerRadius: CGFloat
    let fillOpacity: Double
    let hoverScale: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isHovering && isEnabled ? fillOpacity : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isHovering && isEnabled ? fillOpacity * 0.9 : 0), lineWidth: 1)
            }
            .brightness(isHovering && isEnabled ? 0.045 : 0)
            .scaleEffect(configuration.isPressed ? 0.975 : (isHovering && isEnabled ? hoverScale : 1))
            .offset(y: isHovering && isEnabled && !configuration.isPressed ? -1 : 0)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in
                isHovering = hovering
                (hovering && isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
            .onDisappear {
                if isHovering { NSCursor.arrow.set() }
            }
    }
}

struct StatusDot: View {
    var color: Color = LoomTheme.green
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .shadow(color: color.opacity(0.8), radius: 5)
    }
}

struct TrustedShieldBadge: View {
    var size: CGFloat = 17
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.035, green: 0.085, blue: 0.16))
                .overlay(Circle().stroke(LoomTheme.green.opacity(0.55), lineWidth: 0.7))
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(LoomTheme.green)
        }
        .frame(width: size, height: size)
        .shadow(color: LoomTheme.green.opacity(0.22), radius: 3)
        .accessibilityLabel("Trusted device")
    }
}

struct DeviceGlyph: View {
    let kind: DeviceKind
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [kind.tint.opacity(0.52), Color.blue.opacity(0.15)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(kind.tint.opacity(0.65), lineWidth: 1)
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.43, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: kind.tint.opacity(0.36), radius: 9)
    }
}
