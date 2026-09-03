import AppKit

@MainActor
final class StatusItemController {
    private let item: NSStatusItem
    private let onToggle: () -> Void
    private let menu: NSMenu

    var button: NSStatusBarButton? { item.button }

    init(onToggle: @escaping () -> Void, menu: NSMenu) {
        self.onToggle = onToggle
        self.menu = menu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Stasks")
            b.image?.isTemplate = true
            b.imagePosition = .imageLeading
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        update(count: 0, hasError: false)
    }

    func update(count: Int, hasError: Bool) {
        guard let b = item.button else { return }
        let title = NSMutableAttributedString(string: count > 0 ? " \(count)" : "",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)])
        if hasError {
            title.append(NSAttributedString(string: " ●", attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.systemFont(ofSize: 8)]))
        }
        b.attributedTitle = title
    }

    @objc private func clicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            onToggle()
        }
    }
}
