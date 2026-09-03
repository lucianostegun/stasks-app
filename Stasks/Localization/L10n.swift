import Foundation
import Observation

/// Runtime string lookup. The active bundle is observable, so any SwiftUI body that calls `L()` re-renders when the language changes.
@Observable
final class L10n {
    static let shared = L10n()

    private(set) var bundle: Bundle
    private let english: Bundle

    private init() {
        english = Self.bundle(for: "en") ?? .main
        bundle = english
    }

    func apply(_ language: AppLanguage) {
        let code = language.code ?? Self.systemCode()
        bundle = Self.bundle(for: code) ?? english
    }

    /// Missing keys in the active language fall back to English, then to the key itself.
    func string(_ key: String) -> String {
        let fallback = english.localizedString(forKey: key, value: key, table: nil)
        return bundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    private static func bundle(for code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    private static func systemCode() -> String {
        Bundle.preferredLocalizations(from: AppLanguage.bundledCodes).first ?? "en"
    }
}

func L(_ key: String) -> String { L10n.shared.string(key) }

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.shared.string(key), locale: nil, arguments: args)
}
