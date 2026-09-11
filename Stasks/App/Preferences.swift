import Foundation
import Observation
import StasksCore

enum HotKeyChoice: String, CaseIterable, Identifiable {
    case optCmdS, ctrlOptS, optCmdT, ctrlOptSpace
    var id: String { rawValue }
    var label: String {
        switch self {
        case .optCmdS: return "⌥⌘S"
        case .ctrlOptS: return "⌃⌥S"
        case .optCmdT: return "⌥⌘T"
        case .ctrlOptSpace: return "⌃⌥Space"
        }
    }
    /// Carbon virtual key codes and modifier masks.
    var keyCode: UInt32 {
        switch self {
        case .optCmdS, .ctrlOptS: return 1      // kVK_ANSI_S
        case .optCmdT: return 17                // kVK_ANSI_T
        case .ctrlOptSpace: return 49           // kVK_Space
        }
    }
    var modifiers: UInt32 {
        let cmd: UInt32 = 1 << 8, opt: UInt32 = 1 << 11, ctrl: UInt32 = 1 << 12  // cmdKey, optionKey, controlKey
        switch self {
        case .optCmdS, .optCmdT: return cmd | opt
        case .ctrlOptS, .ctrlOptSpace: return ctrl | opt
        }
    }
}

/// Which backend writes Slack task titles.
enum TitleProvider: String, CaseIterable, Identifiable {
    case anthropic, openAI, claudeCode
    var id: String { rawValue }
    var label: String {
        switch self {
        case .anthropic: return "Anthropic API"
        case .openAI: return "OpenAI-compatible"
        case .claudeCode: return "Claude Code CLI"
        }
    }
}

@Observable
final class Preferences {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    var language: AppLanguage { didSet { d.set(language.rawValue, forKey: "language"); L10n.shared.apply(language) } }
    var order: StackOrder { didSet { d.set(order.rawValue, forKey: "order") } }
    var hideDoneAfterHours: Double { didSet { d.set(hideDoneAfterHours, forKey: "hideDoneAfterHours") } }
    var llmEnabled: Bool { didSet { d.set(llmEnabled, forKey: "llmEnabled") } }
    var titleProvider: TitleProvider { didSet { d.set(titleProvider.rawValue, forKey: "titleProvider") } }
    var openAIBaseURL: String { didSet { d.set(openAIBaseURL, forKey: "openAIBaseURL") } }
    var openAIModel: String { didSet { d.set(openAIModel, forKey: "openAIModel") } }
    var claudeCodeModel: String { didSet { d.set(claudeCodeModel, forKey: "claudeCodeModel") } }
    /// Empty = auto-detect via `ClaudeCodeClient.locate()`.
    var claudeCodePath: String { didSet { d.set(claudeCodePath, forKey: "claudeCodePath") } }
    var pollInterval: Double { didSet { d.set(pollInterval, forKey: "pollInterval") } }
    var hotKey: HotKeyChoice { didSet { d.set(hotKey.rawValue, forKey: "hotKey") } }
    var pinned: Bool { didSet { d.set(pinned, forKey: "pinned") } }
    var soundEnabled: Bool { didSet { d.set(soundEnabled, forKey: "soundEnabled") } }
    var soundName: String { didSet { d.set(soundName, forKey: "soundName") } }
    /// 0...1, applied to `NSSound.volume`.
    var soundVolume: Double { didSet { d.set(soundVolume, forKey: "soundVolume") } }
    var completedCollapsed: Bool { didSet { d.set(completedCollapsed, forKey: "completedCollapsed") } }
    /// Set when the setup assistant was dismissed once. It still opens from the menu.
    var setupCompleted: Bool { didSet { d.set(setupCompleted, forKey: "setupCompleted") } }
    /// Persisted as two Doubles so the panel origin never contends with state.json, which the Slack poller also writes.
    /// nil = the panel height follows its content; a value = the user dragged the bottom edge.
    var panelHeight: Double? {
        didSet {
            if let h = panelHeight { d.set(h, forKey: "panelHeight") } else { d.removeObject(forKey: "panelHeight") }
        }
    }

    var panelOrigin: CGPoint? {
        didSet {
            if let o = panelOrigin {
                d.set(Double(o.x), forKey: "panelOriginX"); d.set(Double(o.y), forKey: "panelOriginY")
            } else {
                d.removeObject(forKey: "panelOriginX"); d.removeObject(forKey: "panelOriginY")
            }
        }
    }

    private init() {
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .system
        order = StackOrder(rawValue: d.string(forKey: "order") ?? "") ?? .lifo
        hideDoneAfterHours = d.object(forKey: "hideDoneAfterHours") as? Double ?? 8
        llmEnabled = d.object(forKey: "llmEnabled") as? Bool ?? true
        titleProvider = TitleProvider(rawValue: d.string(forKey: "titleProvider") ?? "") ?? .anthropic
        openAIBaseURL = d.string(forKey: "openAIBaseURL") ?? OpenAICompatibleClient.defaultBaseURL
        openAIModel = d.string(forKey: "openAIModel") ?? OpenAICompatibleClient.defaultModel
        claudeCodeModel = d.string(forKey: "claudeCodeModel") ?? ClaudeCodeClient.defaultModel
        claudeCodePath = d.string(forKey: "claudeCodePath") ?? ""
        pollInterval = d.object(forKey: "pollInterval") as? Double ?? 15
        hotKey = HotKeyChoice(rawValue: d.string(forKey: "hotKey") ?? "") ?? .optCmdS
        pinned = d.bool(forKey: "pinned")
        soundEnabled = d.object(forKey: "soundEnabled") as? Bool ?? true
        soundName = d.string(forKey: "soundName") ?? AttentionSound.fallbackName
        soundVolume = d.object(forKey: "soundVolume") as? Double ?? 0.7
        completedCollapsed = d.object(forKey: "completedCollapsed") as? Bool ?? true
        setupCompleted = d.bool(forKey: "setupCompleted")
        panelHeight = d.object(forKey: "panelHeight") as? Double
        if let x = d.object(forKey: "panelOriginX") as? Double, let y = d.object(forKey: "panelOriginY") as? Double {
            panelOrigin = CGPoint(x: x, y: y)
        } else {
            panelOrigin = nil
        }
        L10n.shared.apply(language)
    }
}
