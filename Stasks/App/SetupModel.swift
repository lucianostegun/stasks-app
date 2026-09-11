import AppKit
import Observation
import StasksCore

/// First-run checklist. Each item reports a state and, when something is missing, the one action that fixes it.
/// Re-evaluated on demand and every couple of seconds while the window is open, so installing jq or granting a
/// permission in another window shows up without a click.
@MainActor
@Observable
final class SetupModel {
    enum State { case ok, warning, error, off }

    struct Action {
        let label: String
        let run: () -> Void
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let detail: String
        let state: State
        let required: Bool
        let action: Action?
    }

    /// Terminals Stasks can script tab by tab. Others only get activated, which needs no permission.
    static let scriptableTerminals: [(bundleId: String, name: String)] = [
        ("com.googlecode.iterm2", "iTerm2"),
        ("com.apple.Terminal", "Terminal"),
    ]

    let prefs: Preferences
    let settings: SettingsModel
    var items: [Item] = []
    var message: String?

    @ObservationIgnored var onOpenSettings: (SettingsTab) -> Void = { _ in }
    @ObservationIgnored var onFinished: () -> Void = {}
    @ObservationIgnored private var timer: Timer?

    init(prefs: Preferences, settings: SettingsModel) {
        self.prefs = prefs
        self.settings = settings
        refresh()
    }

    var hasBlockingProblem: Bool { items.contains { $0.required && $0.state == .error } }

    func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopAutoRefresh() { timer?.invalidate(); timer = nil }

    func finish() {
        prefs.setupCompleted = true
        stopAutoRefresh()
        onFinished()
    }

    func refresh() {
        settings.refreshHookStatus()
        var list: [Item] = [claudeItem(), jqItem(), hooksItem()]
        for t in Self.scriptableTerminals where AutomationPermission.isInstalled(bundleId: t.bundleId) {
            list.append(automationItem(bundleId: t.bundleId, name: t.name))
        }
        list.append(launchAtLoginItem())
        list.append(slackItem())
        items = list
    }

    // MARK: Items

    private func claudeItem() -> Item {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let path = ClaudeCodeClient.locate() {
            return Item(id: "claude", title: "Claude Code", detail: L("setup.found", path), state: .ok, required: true, action: nil)
        }
        // Installs outside the known locations (nvm, custom prefix) still leave ~/.claude behind once used.
        if FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path) {
            return Item(id: "claude", title: "Claude Code", detail: L("setup.claude.viaHome"), state: .ok, required: true, action: nil)
        }
        return Item(id: "claude", title: "Claude Code", detail: L("setup.claude.missing"), state: .error, required: true,
                    action: Action(label: L("setup.claude.action")) { NSWorkspace.shared.open(URL(string: "https://claude.com/claude-code")!) })
    }

    private func jqItem() -> Item {
        if let path = ToolLocator.locate("jq") {
            return Item(id: "jq", title: "jq", detail: L("setup.found", path), state: .ok, required: true, action: nil)
        }
        return Item(id: "jq", title: "jq", detail: L("setup.jq.missing"), state: .error, required: true,
                    action: Action(label: L("setup.jq.action")) { [weak self] in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install jq", forType: .string)
                        self?.message = L("setup.copied", "brew install jq")
                    })
    }

    private func hooksItem() -> Item {
        let title = L("settings.claude.hooks")
        switch settings.hookStatus {
        case .installed:
            return Item(id: "hooks", title: title, detail: L("setup.hooks.ok"), state: .ok, required: true, action: nil)
        case .outdated:
            return Item(id: "hooks", title: title, detail: L("setup.hooks.outdated"), state: .warning, required: true,
                        action: Action(label: L("setup.hooks.update")) { [weak self] in self?.installHooks() })
        case .missing:
            return Item(id: "hooks", title: title, detail: L("setup.hooks.missing"), state: .error, required: true,
                        action: Action(label: L("setup.hooks.install")) { [weak self] in self?.installHooks() })
        }
    }

    private func installHooks() {
        settings.installHooks()
        message = settings.hookMessage
        refresh()
    }

    private func automationItem(bundleId: String, name: String) -> Item {
        let id = "automation." + bundleId
        let title = L("setup.automation.title", name)
        switch AutomationPermission.check(bundleId: bundleId, ask: false) {
        case .granted:
            return Item(id: id, title: title, detail: L("setup.automation.ok"), state: .ok, required: false, action: nil)
        case .denied:
            return Item(id: id, title: title, detail: L("setup.automation.denied"), state: .warning, required: false,
                        action: Action(label: L("setup.automation.systemSettings")) { AutomationPermission.openSystemSettings() })
        case .notDetermined:
            return Item(id: id, title: title, detail: L("setup.automation.notAsked"), state: .warning, required: false,
                        action: Action(label: L("setup.automation.request")) { [weak self] in self?.requestAutomation(bundleId: bundleId) })
        case .targetNotRunning:
            return Item(id: id, title: title, detail: L("setup.automation.notRunning", name), state: .off, required: false,
                        action: Action(label: L("setup.automation.open", name)) { [weak self] in self?.requestAutomation(bundleId: bundleId) })
        case let .unknown(code):
            return Item(id: id, title: title, detail: L("common.failure", "OSStatus \(code)"), state: .warning, required: false, action: nil)
        }
    }

    /// The consent dialog only appears while the target runs, so launch it first when needed. The blocking call
    /// runs off the main thread; the list refreshes once the user answers.
    private func requestAutomation(bundleId: String) {
        let ask = { [weak self] in
            Task.detached {
                _ = AutomationPermission.check(bundleId: bundleId, ask: true)
                await MainActor.run { self?.refresh() }
            }
        }
        if AutomationPermission.isRunning(bundleId: bundleId) { ask(); return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ask() }
        }
    }

    private func launchAtLoginItem() -> Item {
        if settings.launchAtLogin {
            return Item(id: "login", title: L("settings.launchAtLogin"), detail: L("setup.login.on"), state: .ok, required: false, action: nil)
        }
        return Item(id: "login", title: L("settings.launchAtLogin"), detail: L("setup.login.off"), state: .off, required: false,
                    action: Action(label: L("setup.enable")) { [weak self] in self?.settings.launchAtLogin = true; self?.refresh() })
    }

    private func slackItem() -> Item {
        if !(KeychainStore.get(KeychainStore.slackToken) ?? "").isEmpty {
            return Item(id: "slack", title: "Slack", detail: L("setup.slack.ok"), state: .ok, required: false, action: nil)
        }
        return Item(id: "slack", title: "Slack", detail: L("setup.slack.missing"), state: .off, required: false,
                    action: Action(label: L("setup.configure")) { [weak self] in self?.onOpenSettings(.slack) })
    }
}
