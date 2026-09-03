import AppKit
import SwiftUI
import StasksCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!
    private var panel: PanelController!
    private var store: TaskStore!
    private var model: PanelModel!
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

        let menu = NSMenu()
        menu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem = StatusItemController(onToggle: { [weak self] in self?.panel.toggle(anchor: self?.statusItem.button) }, menu: menu)
        observeStore()
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
