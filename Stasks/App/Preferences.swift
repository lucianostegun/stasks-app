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

@Observable
final class Preferences {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    var order: StackOrder { didSet { d.set(order.rawValue, forKey: "order") } }
    var hideDoneAfterHours: Double { didSet { d.set(hideDoneAfterHours, forKey: "hideDoneAfterHours") } }
    var llmEnabled: Bool { didSet { d.set(llmEnabled, forKey: "llmEnabled") } }
    var pollInterval: Double { didSet { d.set(pollInterval, forKey: "pollInterval") } }
    var hotKey: HotKeyChoice { didSet { d.set(hotKey.rawValue, forKey: "hotKey") } }
    var pinned: Bool { didSet { d.set(pinned, forKey: "pinned") } }
    var completedCollapsed: Bool { didSet { d.set(completedCollapsed, forKey: "completedCollapsed") } }
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
        order = StackOrder(rawValue: d.string(forKey: "order") ?? "") ?? .lifo
        hideDoneAfterHours = d.object(forKey: "hideDoneAfterHours") as? Double ?? 8
        llmEnabled = d.object(forKey: "llmEnabled") as? Bool ?? true
        pollInterval = d.object(forKey: "pollInterval") as? Double ?? 15
        hotKey = HotKeyChoice(rawValue: d.string(forKey: "hotKey") ?? "") ?? .optCmdS
        pinned = d.bool(forKey: "pinned")
        completedCollapsed = d.object(forKey: "completedCollapsed") as? Bool ?? true
        panelHeight = d.object(forKey: "panelHeight") as? Double
        if let x = d.object(forKey: "panelOriginX") as? Double, let y = d.object(forKey: "panelOriginY") as? Double {
            panelOrigin = CGPoint(x: x, y: y)
        } else {
            panelOrigin = nil
        }
    }
}
