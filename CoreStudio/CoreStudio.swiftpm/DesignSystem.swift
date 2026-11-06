import SwiftUI

// MARK: - CoreStudio Design System
//
// One place for every visual decision. Views use these tokens and components
// instead of raw colors, sizes and fonts, so the whole app stays consistent
// and a change here restyles everything.

enum DS {

    // MARK: Colors
    enum Palette {
        // Surfaces, darkest to lightest
        static let canvas = Color(hex: 0x0B0C0F)        // behind everything
        static let panel = Color(hex: 0x131519)         // panels
        static let raised = Color(hex: 0x1B1E24)        // cards, fields inside panels
        static let hover = Color(hex: 0x252932)         // pressed / selected rows
        static let stroke = Color.white.opacity(0.07)   // hairlines
        static let strokeStrong = Color.white.opacity(0.14)

        // Text
        static let textPrimary = Color(hex: 0xECEEF2)
        static let textSecondary = Color(hex: 0x9AA0AC)
        static let textTertiary = Color(hex: 0x5F6573)

        // Brand & roles
        static let accent = Color(hex: 0x7C5CFF)        // violet
        static let accentSoft = Color(hex: 0x7C5CFF).opacity(0.18)
        static let keyframe = Color(hex: 0xFFC53D)      // amber
        static let playhead = Color(hex: 0xFF3B5C)
        static let danger = Color(hex: 0xFF5A5F)
        static let success = Color(hex: 0x2FD27A)

        // Timeline
        static let videoClip = Color(hex: 0x4F5BD5)
        static let videoClipSelected = Color(hex: 0x6E7BFF)
        static let audioClip = Color(hex: 0x1F9D63)
        static let audioClipSelected = Color(hex: 0x2FD27A)
        static let trackLane = Color(hex: 0x16181D)
        static let ruler = Color(hex: 0x1B1E24)
    }

    // MARK: Spacing (4-pt grid)
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: Corner radius
    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
    }

    // MARK: Type
    enum Typo {
        static let appTitle = Font.system(size: 15, weight: .semibold)
        static let panelTitle = Font.system(size: 12, weight: .semibold)
        static let sectionTitle = Font.system(size: 11, weight: .semibold)
        static let label = Font.system(size: 11, weight: .medium)
        static let value = Font.system(size: 11, weight: .medium, design: .monospaced)
        static let caption = Font.system(size: 10, weight: .regular)
        static let timecode = Font.system(size: 13, weight: .semibold, design: .monospaced)
        static let clip = Font.system(size: 10, weight: .semibold)
    }

    // MARK: Sizes
    enum Size {
        static let toolbarHeight: CGFloat = 52
        static let panelHeader: CGFloat = 36
        static let iconButton: CGFloat = 32
        static let trackHeight: CGFloat = 56
        static let trackGap: CGFloat = 6
        static let rulerHeight: CGFloat = 24
        static let trackHeaderWidth: CGFloat = 0
    }
}

// MARK: - Color helper

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Components

/// The header strip at the top of every panel.
struct PanelHeader<Trailing: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Palette.textSecondary)
            Text(title.uppercased())
                .font(DS.Typo.panelTitle)
                .tracking(0.8)
                .foregroundColor(DS.Palette.textSecondary)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: DS.Size.panelHeader)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.stroke).frame(height: 1) }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, icon: String) {
        self.init(title: title, icon: icon) { EmptyView() }
    }
}

/// A panel: rounded surface with a hairline border.
struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DS.Palette.panel)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).stroke(DS.Palette.stroke, lineWidth: 1))
    }
}

extension View {
    func dsPanel() -> some View { modifier(PanelModifier()) }
}

/// Square icon button used in toolbars and panel headers.
struct IconButton: View {
    let systemName: String
    var isActive: Bool = false
    var tint: Color = DS.Palette.textPrimary
    var size: CGFloat = DS.Size.iconButton
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundColor(isActive ? DS.Palette.accent : tint)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(isActive ? DS.Palette.accentSoft : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Dims slightly while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Filled (primary) or tinted (secondary) text button.
struct DSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.label)
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s - 1)
            .foregroundColor(foreground)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).fill(background)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return DS.Palette.textPrimary
        case .danger: return DS.Palette.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return DS.Palette.accent
        case .secondary: return DS.Palette.raised
        case .danger: return DS.Palette.danger.opacity(0.12)
        }
    }
}

/// A titled group inside a panel (Inspector sections).
struct SectionCard<Content: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.xs) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                }
                Text(title.uppercased()).font(DS.Typo.sectionTitle).tracking(0.6)
            }
            .foregroundColor(DS.Palette.textTertiary)

            VStack(alignment: .leading, spacing: DS.Space.m) {
                content()
            }
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
        }
    }
}

/// Small pill, e.g. "2x" or a category.
struct Chip: View {
    let text: String
    var color: Color = DS.Palette.textSecondary

    var body: some View {
        Text(text)
            .font(DS.Typo.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// An empty state with icon and message.
struct EmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: DS.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundColor(DS.Palette.textTertiary)
            Text(title).font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
            if let message {
                Text(message).font(DS.Typo.caption).foregroundColor(DS.Palette.textTertiary).multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Timecode text HH:MM:SS:FF.
func formatTimecode(_ seconds: Double, fps: Double) -> String {
    guard seconds.isFinite, fps > 0 else { return "00:00:00:00" }
    let totalFrames = Int((max(0, seconds) * fps).rounded())
    let f = Int(fps.rounded())
    let frames = totalFrames % max(f, 1)
    let totalSeconds = totalFrames / max(f, 1)
    return String(format: "%02d:%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds / 60) % 60, totalSeconds % 60, frames)
}
