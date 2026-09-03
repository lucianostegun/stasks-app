import AppKit
import SwiftUI
import StasksCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Preferences.shared
    private var settingsWindow: NSWindow?
    private var settingsMenuItem: NSMenuItem?
    private var hooksMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?
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
    private let attentionSound = AttentionSound()
    private var purgeTimer: Timer?
    private var watchedSessionIds: Set<String> = []
    var settingsModel: SettingsModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        _ = AppState.load(from: stateURL, now: Date()).saveIfNew(to: stateURL)

        store = TaskStore(persistence: JSONFilePersistence(url: supportDir.appendingPathComponent("tasks.json")))
        store.purgeCompleted(olderThanDays: 7)
        store.onAttentionRequested = { [weak self] _ in
            guard let self else { return }
            self.attentionSound.play(self.prefs)
        }

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
        model.manualHeight = prefs.panelHeight.map { CGFloat($0) }
        model.onResetHeight = { [weak self] in self?.panel.resetHeight() }
        panel.onManualHeightChanged = { [weak self] h in self?.model.manualHeight = h }
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
        let settings = menu.addItem(withTitle: L("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settingsMenuItem = settings
        let hooks = menu.addItem(withTitle: L("menu.hooks.install"), action: #selector(installHooks), keyEquivalent: "")
        hooks.target = self
        hooksMenuItem = hooks
        menu.addItem(.separator())
        quitMenuItem = menu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem = StatusItemController(onToggle: { [weak self] in self?.togglePanel() }, menu: menu)
    }

    /// Titles are re-read on every open: the hooks item reflects the real state of ~/.claude/settings.json,
    /// and all items pick up a language change made in Settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        settingsMenuItem?.title = L("menu.settings")
        quitMenuItem?.title = L("menu.quit")
        guard let item = hooksMenuItem, let sm = settingsModel else { return }
        sm.refreshHookStatus()
        switch sm.hookStatus {
        case .installed:
            item.title = L("menu.hooks.installed")
            item.isEnabled = false
        case .outdated:
            item.title = L("menu.hooks.update")
            item.isEnabled = true
        case .missing:
            item.title = L("menu.hooks.install")
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
        transcripts = TranscriptWatcher(onTitle: { [weak self] sessionId, title in
            Task { @MainActor in
                guard let self, let t = self.store.task(claudeSessionId: sessionId) else { return }
                self.store.setTitle(id: t.id, title, pinned: true)
            }
        }, onMessage: { [weak self] sessionId, text in
            // Subtitle shows the start of Claude's latest answer instead of the working folder.
            Task { @MainActor in
                guard let self, let t = self.store.task(claudeSessionId: sessionId) else { return }
                self.store.setSubtitle(id: t.id, TaskItem.truncatedTitle(text))
            }
        })
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
                Task { @MainActor in self?.model.llmError = ok ? nil : L("panel.llmError") }
            })
        poller = SlackPoller(store: store, stateURL: stateURL, clientProvider: {
            guard let token = KeychainStore.get(KeychainStore.slackToken), !token.isEmpty else { return nil }
            return SlackClient(token: token)
        }, titleGenerator: titles, interval: prefs.pollInterval)
        poller.start()
    }

    /// Builds the provider client at call time so Settings changes apply without restart.
    /// `onOutcome(false)` means a provider was configured and enabled but generation failed, which is what the red dot reports.
    private struct LLMTitleGate: TitleGenerating {
        let isEnabled: @Sendable () async -> Bool
        let onOutcome: @Sendable (Bool) -> Void
        func title(channel: String, author: String, text: String, thread: [(author: String, text: String)]) async -> String? {
            guard await isEnabled(), let client = await MainActor.run(body: { TitleClientFactory.make(Preferences.shared) }) else { return nil }
            let generated = await TitleGenerator(client: client).title(channel: channel, author: author, text: text, thread: thread)
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
                               titleClientFactory: { TitleClientFactory.make($0) })
        sm.onCredentialsChanged = { [weak self] in self?.poller.reauthenticate(); self?.refreshCredentialState() }
        sm.onHotKeyChanged = { [weak self] in self?.hotKey.register($0) }
        sm.onPollIntervalChanged = { [weak self] in self?.poller.interval = $0 }
        settingsModel = sm
        observeTitleProvider()
    }

    /// The unconfigured banner only matters once Slack is configured, since the LLM is used for Slack titles alone.
    private func refreshCredentialState() {
        let hasSlack = !(KeychainStore.get(KeychainStore.slackToken) ?? "").isEmpty
        model.titleProviderUnconfigured = hasSlack && !TitleClientFactory.isConfigured(prefs)
    }

    /// Provider fields live in Preferences, so a change there re-evaluates the banner without a credential save.
    private func observeTitleProvider() {
        withObservationTracking {
            _ = prefs.titleProvider; _ = prefs.claudeCodePath; _ = prefs.claudeCodeModel; _ = prefs.openAIBaseURL; _ = prefs.openAIModel
            refreshCredentialState()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitleProvider() }
        }
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
