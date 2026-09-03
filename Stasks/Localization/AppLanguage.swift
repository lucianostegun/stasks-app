import Foundation

/// UI language. `system` follows macOS and falls back to English when the system language has no translation.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, pt, es, fr
    var id: String { rawValue }

    /// Every `.lproj` shipped in the bundle. `es` and `fr` exist with English placeholder values until translated.
    static let bundledCodes = ["en", "pt", "es", "fr"]
    /// Languages offered in Settings. Add `.es` / `.fr` here once their `Localizable.strings` are translated.
    static let selectable: [AppLanguage] = [.system, .en, .pt]

    var code: String? { self == .system ? nil : rawValue }

    /// Shown in its own language so the user can find it whatever the current UI language is.
    var nativeName: String {
        switch self {
        case .system: return L("language.system")
        case .en: return "English"
        case .pt: return "Português"
        case .es: return "Español"
        case .fr: return "Français"
        }
    }
}
