import AppKit
import SwiftUI
import StasksCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!
    private var panel: PanelController!
    private let prefs = Preferences.shared
    private let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Stasks")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let placeholder = Text("Stasks").padding().frame(width: Theme.panelWidth, height: 200)
        panel = PanelController(content: placeholder, preferences: prefs, stateURL: supportDir.appendingPathComponent("state.json"))
        let menu = NSMenu()
        menu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem = StatusItemController(onToggle: { [weak self] in self?.panel.toggle(anchor: self?.statusItem.button) }, menu: menu)
        statusItem.update(count: 3, hasError: true)
    }
}
