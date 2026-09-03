import SwiftUI
import StasksCore

enum Theme {
    static let panelWidth: CGFloat = 340
    static let cornerRadius: CGFloat = 16

    static func statusColor(_ s: TaskStatus) -> Color {
        switch s {
        case .open: return Color(red: 0x5a/255, green: 0xa9/255, blue: 0xff/255)
        case .inProgress: return Color(red: 0xff/255, green: 0xb8/255, blue: 0x4d/255)
        case .done: return Color(red: 0x43/255, green: 0xd1/255, blue: 0x7c/255)
        }
    }

    static func sourceColor(_ k: TaskSourceKind) -> Color {
        switch k {
        case .claude: return Color(red: 0xd9/255, green: 0x77/255, blue: 0x57/255)
        case .slack: return Color(red: 0xe0/255, green: 0x1e/255, blue: 0x5a/255)
        case .manual: return Color(red: 0x8a/255, green: 0x90/255, blue: 0xb8/255)
        }
    }

    static func sourceGlyph(_ k: TaskSourceKind) -> String {
        switch k { case .claude: return "✱"; case .slack: return "#"; case .manual: return "✎" }
    }

    /// Panel tint over the blur. Dark Glass / Light Frosted per spec.
    static func panelTint(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 24/255, green: 27/255, blue: 44/255).opacity(0.74) : Color.white.opacity(0.66)
    }
    static func panelBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.9)
    }
    static func rowHover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.7)
    }
    static func chip(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    static let accent = Color(red: 0x6f/255, green: 0x7c/255, blue: 0xff/255)
}
