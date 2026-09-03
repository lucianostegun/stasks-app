import AppKit
import SwiftUI
import StasksCore

@MainActor
final class PanelController {
    private let window = StackPanelWindow()
    private let preferences: Preferences
    private let stateURL: URL
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastAnchorFrame: NSRect?
    private var contentSize = CGSize(width: Theme.panelWidth, height: 200)

    var isVisible: Bool { window.isVisible }

    init(content: some View, preferences: Preferences, stateURL: URL) {
        self.preferences = preferences
        self.stateURL = stateURL

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Theme.cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        window.contentView = effect
        window.onEscape = { [weak self] in if self?.preferences.pinned == false { self?.hide() } }

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.persistOrigin() }
        }
        setPinned(preferences.pinned)
    }

    // MARK: Show / hide

    func toggle(anchor: NSStatusBarButton?) { isVisible ? hide() : show(anchor: anchor) }

    func show(anchor: NSStatusBarButton?) {
        if let anchor, let w = anchor.window { lastAnchorFrame = w.convertToScreen(anchor.convert(anchor.bounds, to: nil)) }
        layout()
        window.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func hide() {
        window.orderOut(nil)
        removeMonitors()
    }

    func setPinned(_ pinned: Bool) {
        window.level = pinned ? .floating : .popUpMenu
        window.isMovableByWindowBackground = pinned
        if isVisible { layout() }
        if !pinned { installMonitors() } else { removeMonitors() }
    }

    func contentSizeChanged(_ size: CGSize) {
        guard size.height > 0, abs(size.height - contentSize.height) > 0.5 else { return }
        contentSize = CGSize(width: Theme.panelWidth, height: size.height)
        if isVisible { layout(animated: true) }
    }

    // MARK: Layout

    private func layout(animated: Bool = false) {
        let size = contentSize
        var origin: NSPoint
        let state = AppState.load(from: stateURL, now: Date())
        if preferences.pinned, let saved = state.panelOrigin {
            origin = NSPoint(x: saved.x, y: saved.y)
        } else if let a = lastAnchorFrame {
            origin = NSPoint(x: a.midX - size.width / 2, y: a.minY - size.height - 6)
        } else {
            origin = window.frame.origin
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(lastAnchorFrame?.origin ?? origin) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            origin.x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
            origin.y = max(origin.y, v.minY + 8)
        }
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: animated && isVisible)
    }

    var maxListHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return screen * 0.7 - 120
    }

    private func persistOrigin() {
        guard preferences.pinned else { return }
        var s = AppState.load(from: stateURL, now: Date())
        s.panelOrigin = window.frame.origin
        try? s.save(to: stateURL)
    }

    // MARK: Click outside

    private func installMonitors() {
        guard !preferences.pinned, globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible, event.window != self.window else { return event }
            self.hide()
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }
}
