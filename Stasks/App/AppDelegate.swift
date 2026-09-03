import AppKit
import SwiftUI
import StasksCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!
    private var panel: PanelController!
    private var store: TaskStore!
    private var model: PanelModel!
    var settingsModel: SettingsModel?
    private let prefs = Preferences.shared
    private let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Stasks")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = TaskStore(persistence: JSONFilePersistence(url: supportDir.appendingPathComponent("tasks.json")))
        model = PanelModel(store: store, prefs: prefs)
        panel = PanelController(content: StackPanelView(model: model), preferences: prefs, stateURL: supportDir.appendingPathComponent("state.json"))
        model.maxListHeight = panel.maxListHeight
        model.onSizeChange = { [weak self] in self?.panel.contentSizeChanged($0) }
        model.onPinChanged = { [weak self] in self?.panel.setPinned($0) }

        let claudeSettingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        let hookInstaller = HookInstaller(settingsURL: claudeSettingsURL, scriptPath: Bundle.main.path(forResource: "stasks-hook", ofType: "sh") ?? "")
        settingsModel = SettingsModel(prefs: prefs, hookInstaller: hookInstaller,
                                       slackTestFactory: { SlackClient(token: $0) },
                                       anthropicTestFactory: { AnthropicClient(apiKey: $0) })

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let installHooksItem = NSMenuItem(title: "Instalar hooks do Claude", action: #selector(installHooks), keyEquivalent: "")
        installHooksItem.target = self
        menu.addItem(installHooksItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem = StatusItemController(onToggle: { [weak self] in self?.panel.toggle(anchor: self?.statusItem.button) }, menu: menu)
        observeStore()
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
    }

    @MainActor
    @objc private func installHooks() {
        settingsModel?.installHooks()
    }

    @MainActor
    private func observeStore() {
        withObservationTracking {
            statusItem.update(count: store.activeCount, hasError: model.errorBanner != nil)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }
}
