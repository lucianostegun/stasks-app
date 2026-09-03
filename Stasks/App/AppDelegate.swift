import AppKit
import SwiftUI
import StasksCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences.shared
    private let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Stasks")
    private var stateURL: URL { supportDir.appendingPathComponent("state.json") }

    private var store: TaskStore!
    private var model: PanelModel!
    private var panel: PanelController!
    private var statusItem: StatusItemController!
    private var drainer: InboxDrainer!
    private var transcripts: TranscriptWatcher!
    private var poller: SlackPoller!
    private let hotKey = HotKeyManager()
    private var purgeTimer: Timer?
    var settingsModel: SettingsModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        _ = AppState.load(from: stateURL, now: Date()).saveIfNew(to: stateURL)

        store = TaskStore(persistence: JSONFilePersistence(url: supportDir.appendingPathComponent("tasks.json")))
        store.purgeCompleted(olderThanDays: 7)

        setupPanel()
        setupStatusItem()
        setupClaude()
        setupSlack()
        setupSettings()
        setupHotKey()
        setupLifecycle()
        observeStore()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
        drainer.stop(); transcripts.unwatchAll(); poller.stop()
    }

    // MARK: Panel + status item

    private func setupPanel() {
        model = PanelModel(store: store, prefs: prefs)
        panel = PanelController(content: StackPanelView(model: model), preferences: prefs, stateURL: stateURL)
        model.maxListHeight = panel.maxListHeight
        model.onSizeChange = { [weak self] in self?.panel.contentSizeChanged($0) }
        model.onPinChanged = { [weak self] in self?.panel.setPinned($0) }
        model.onOpenSettings = { [weak self] in self?.openSettings() }
    }

    private func setupStatusItem() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Instalar hooks do Claude", action: #selector(installHooks), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem = StatusItemController(onToggle: { [weak self] in self?.togglePanel() }, menu: menu)
    }

    private func togglePanel() { panel.toggle(anchor: statusItem.button) }

    private func observeStore() {
        withObservationTracking {
            statusItem.update(count: store.activeCount, hasError: model.errorBanner != nil)
            model.slackState = poller.connectionState
            syncTranscriptWatchers()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    // MARK: Claude

    private func setupClaude() {
        let processor = InboxProcessor(store: store)
        transcripts = TranscriptWatcher { [weak self] sessionId, title in
            Task { @MainActor in
                guard let self, let t = self.store.task(claudeSessionId: sessionId) else { return }
                self.store.setTitle(id: t.id, title, pinned: true)
            }
        }
        drainer = InboxDrainer(directory: supportDir) { events in
            Task { @MainActor in processor.apply(events) }
        }
        drainer.start()
    }

    private func syncTranscriptWatchers() {
        for t in store.tasks {
            guard case let .claude(sessionId, path, _, _) = t.source else { continue }
            if t.status.isActive { transcripts.watch(sessionId: sessionId, path: path) } else { transcripts.unwatch(sessionId: sessionId) }
        }
    }

    // MARK: Slack + LLM

    private func setupSlack() {
        let prefs = self.prefs
        let titles: (any TitleGenerating)? = LLMTitleGate(prefs: prefs)
        poller = SlackPoller(store: store, stateURL: stateURL, clientProvider: {
            guard let token = KeychainStore.get(KeychainStore.slackToken), !token.isEmpty else { return nil }
            return SlackClient(token: token)
        }, titleGenerator: titles, interval: prefs.pollInterval)
        poller.start()
    }

    /// Reads the key and toggle at call time so Settings changes apply without restart.
    private struct LLMTitleGate: TitleGenerating {
        let prefs: Preferences
        func title(channel: String, author: String, text: String, thread: [(author: String, text: String)]) async -> String? {
            let enabled = await MainActor.run { prefs.llmEnabled }
            guard enabled, let key = KeychainStore.get(KeychainStore.anthropicKey), !key.isEmpty else { return nil }
            return await TitleGenerator(client: AnthropicClient(apiKey: key)).title(channel: channel, author: author, text: text, thread: thread)
        }
    }

    // MARK: Settings

    private func setupSettings() {
        let scriptPath = Bundle.main.path(forResource: "stasks-hook", ofType: "sh") ?? ""
        let installer = HookInstaller(settingsURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"), scriptPath: scriptPath)
        let sm = SettingsModel(prefs: prefs, hookInstaller: installer,
                               slackTestFactory: { SlackClient(token: $0) },
                               anthropicTestFactory: { AnthropicClient(apiKey: $0) })
        sm.onCredentialsChanged = { [weak self] in self?.poller.reauthenticate() }
        sm.onHotKeyChanged = { [weak self] in self?.hotKey.register($0) }
        sm.onPollIntervalChanged = { [weak self] in self?.poller.interval = $0 }
        settingsModel = sm
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func installHooks() {
        settingsModel?.installHooks()
        openSettings()
    }

    // MARK: Hotkey + lifecycle

    private func setupHotKey() {
        hotKey.onPress = { [weak self] in self?.togglePanel() }
        hotKey.register(prefs.hotKey)
    }

    private func setupLifecycle() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.poller.pause() }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.poller.resume(); self?.drainer.drainNow() }
        }
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.purgeCompleted(olderThanDays: 7) }
        }
    }
}
