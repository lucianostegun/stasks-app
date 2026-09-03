import SwiftUI
import Observation
import StasksCore

@MainActor
@Observable
final class PanelModel {
    let store: TaskStore
    let prefs: Preferences
    var slackState: SlackConnectionState = .idle
    var llmError: String?
    /// True when Slack titles want the LLM but the chosen provider has no usable configuration. Refreshed on launch, on credential save and on provider change.
    var titleProviderUnconfigured = false
    var maxListHeight: CGFloat = 500
    /// Set when the user resized the panel; the list then fills the window instead of sizing to content.
    var manualHeight: CGFloat?
    var now = Date()

    @ObservationIgnored var onSizeChange: (CGSize) -> Void = { _ in }
    @ObservationIgnored var onOpenSettings: () -> Void = {}
    @ObservationIgnored var onPinChanged: (Bool) -> Void = { _ in }
    @ObservationIgnored var onResetHeight: () -> Void = {}
    @ObservationIgnored private var ticker: Timer?

    init(store: TaskStore, prefs: Preferences) {
        self.store = store
        self.prefs = prefs
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    var errorBanner: String? {
        if case let .disconnected(reason) = slackState { return L("panel.slackDisconnected", reason) }
        if let llmError { return llmError }
        if prefs.llmEnabled, titleProviderUnconfigured { return L("panel.titlesUnconfigured") }
        return nil
    }

    func createManual(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.add(TaskItem.manual(title: t, now: Date()))
    }
    func open(_ task: TaskItem) { SourceOpener.open(task) }
    func setStatus(_ task: TaskItem, _ s: TaskStatus) { store.setStatus(id: task.id, s) }
    func rename(_ task: TaskItem, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.setTitle(id: task.id, t, pinned: true)
    }
    func remove(_ task: TaskItem) { store.remove(id: task.id) }
    func togglePin() { prefs.pinned.toggle(); onPinChanged(prefs.pinned) }
}
