import AppKit
import SwiftUI
import StasksCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Preferences.shared
    private var settingsWindow: NSWindow?
    private var hooksMenuItem: NSMenuItem?
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
    private var watchedSessionIds: Set<String> = []
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
        observePoller()
        if prefs.pinned { panel.show(anchor: statusItem.button) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
        drainer.stop(); transcripts.unwatchAll(); poller.stop()
    }

    // MARK: Panel + status item

    private func setupPanel() {
        model = PanelModel(store: store, prefs: prefs)
        panel = PanelController(content: StackPanelView(model: model), preferences: prefs)
        model.maxListHeight = panel.maxListHeight
        model.onSizeChange = { [weak self] in self?.panel.contentSizeChanged($0) }
        model.onPinChanged = { [weak self] in self?.panel.setPinned($0) }
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        panel.onShow = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.poller.retryProvisionalTitles()
            }
        }
    }

    private func setupStatusItem() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",").target = self
        let hooks = menu.addItem(withTitle: "Instalar hooks do Claude", action: #selector(installHooks), keyEquivalent: "")
        hooks.target = self
        hooksMenuItem = hooks
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem = StatusItemController(onToggle: { [weak self] in self?.togglePanel() }, menu: menu)
    }

    /// The hooks item reflects the real state of ~/.claude/settings.json every time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let item = hooksMenuItem, let sm = settingsModel else { return }
        sm.refreshHookStatus()
        switch sm.hookStatus {
        case .installed:
            item.title = "Hooks do Claude instalados"
            item.isEnabled = false
        case .outdated:
            item.title = "Atualizar hooks do Claude"
            item.isEnabled = true
        case .missing:
            item.title = "Instalar hooks do Claude"
            item.isEnabled = true
        }
    }

    private func togglePanel() { panel.toggle(anchor: statusItem.button) }

    private func observeStore() {
        withObservationTracking {
            statusItem.update(count: store.activeCount, hasError: model.errorBanner != nil)
            syncTranscriptWatchers()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    /// Kept separate from `observeStore` so mirroring the poller state does not invalidate the store tracking.
    private func observePoller() {
        withObservationTracking {
            model.slackState = poller.connectionState
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.statusItem.update(count: self.store.activeCount, hasError: self.model.errorBanner != nil)
                self.observePoller()
            }
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
        var wanted: Set<String> = []
        for t in store.tasks {
            guard case let .claude(sessionId, path, _, _) = t.source else { continue }
            if t.status.isActive {
                transcripts.watch(sessionId: sessionId, path: path)
                wanted.insert(sessionId)
            } else {
                transcripts.unwatch(sessionId: sessionId)
            }
        }
        // A removed task leaves no row to iterate, so unwatch anything no longer wanted.
        for stale in watchedSessionIds.subtracting(wanted) { transcripts.unwatch(sessionId: stale) }
        watchedSessionIds = wanted
    }

    // MARK: Slack + LLM

    private func setupSlack() {
        let titles: (any TitleGenerating)? = LLMTitleGate(
            isEnabled: { await MainActor.run { Preferences.shared.llmEnabled } },
            onOutcome: { [weak self] ok in
                Task { @MainActor in self?.model.llmError = ok ? nil : "Anthropic: falha ao gerar título" }
            })
        poller = SlackPoller(store: store, stateURL: stateURL, clientProvider: {
            guard let token = KeychainStore.get(KeychainStore.slackToken), !token.isEmpty else { return nil }
            return SlackClient(token: token)
        }, titleGenerator: titles, interval: prefs.pollInterval)
        poller.start()
    }

    /// Reads the key and toggle at call time so Settings changes apply without restart.
    /// `onOutcome(false)` means Anthropic was configured and enabled but generation failed, which is what the red dot reports.
    private struct LLMTitleGate: TitleGenerating {
        let isEnabled: @Sendable () async -> Bool
        let onOutcome: @Sendable (Bool) -> Void
        func title(channel: String, author: String, text: String, thread: [(author: String, text: String)]) async -> String? {
            guard await isEnabled(), let key = KeychainStore.get(KeychainStore.anthropicKey), !key.isEmpty else { return nil }
            let generated = await TitleGenerator(client: AnthropicClient(apiKey: key)).title(channel: channel, author: author, text: text, thread: thread)
            onOutcome(generated != nil)
            return generated
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

    /// Owns its own window: the SwiftUI `Settings` scene's `showSettingsWindow:` selector does not
    /// respond in an accessory (LSUIElement) app driven from a status item.
    @objc func openSettings() {
        guard let sm = settingsModel else { return }
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: sm))
            let w = NSWindow(contentViewController: host)
            w.title = "Stasks"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        sm.refreshHookStatus()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
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
            MainActor.assumeIsolated { self?.poller.resume(); self?.drainer.drainSoon() }
        }
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.purgeCompleted(olderThanDays: 7) }
        }
    }
}
