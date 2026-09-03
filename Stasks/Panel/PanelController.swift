import AppKit
import SwiftUI
import StasksCore

@MainActor
final class PanelController {
    private let window = StackPanelWindow()
    private let preferences: Preferences
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastAnchorFrame: NSRect?
    private weak var anchorWindow: NSWindow?
    private var contentSize = CGSize(width: Theme.panelWidth, height: 200)
    private var savedOrigin: CGPoint?
    /// True while we set the frame ourselves, so a user drag can be told apart from our own layout.
    private var programmaticResize = false

    var isVisible: Bool { window.isVisible }
    /// Called at the end of every `show`, so the app can refresh on-demand work such as provisional title retries.
    var onShow: (() -> Void)?
    /// Fires with the new height after the user drags the bottom edge, or nil when the height goes back to automatic.
    var onManualHeightChanged: ((CGFloat?) -> Void)?

    init(content: some View, preferences: Preferences) {
        self.preferences = preferences
        self.savedOrigin = preferences.panelOrigin

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        // A layer corner radius does not clip a behind-window blur: the WindowServer draws the blur
        // and the window shadow for the full rect. maskImage is the supported way to shape both.
        effect.maskImage = Self.roundedMask(radius: Theme.cornerRadius)

        let hosting = NSHostingView(rootView: content)
        // No SwiftUI-derived min/max constraints on the window: they would pin the window's max height
        // to the content height and block the user's vertical resize. We size the window ourselves.
        hosting.sizingOptions = []
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

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.persistOrigin() }
        }
        nc.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.userResized() }
        }
        nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window.invalidateShadow() }
        }
        // Never use hidesOnDeactivate here: a window hidden that way only comes back when the app
        // activates, and the status item button is non-activating, so the panel would stay gone.
        // Hiding on app deactivation (Cmd-Tab away) is done explicitly instead, unpinned only.
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.preferences.pinned, self.isVisible else { return }
                self.hide()
            }
        }
        setPinned(preferences.pinned)
    }

    // MARK: Show / hide

    func toggle(anchor: NSStatusBarButton?) { isVisible ? hide() : show(anchor: anchor) }

    func show(anchor: NSStatusBarButton?) {
        if let anchor, let w = anchor.window {
            lastAnchorFrame = w.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            anchorWindow = w
        }
        layout()
        window.makeKeyAndOrderFront(nil)
        installMonitors()
        onShow?()
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
        // With a manual height the content fills the window; only automatic mode follows the content.
        if isVisible, preferences.panelHeight == nil { layout(animated: true) }
    }

    /// Back to automatic height (content-sized).
    func resetHeight() {
        preferences.panelHeight = nil
        onManualHeightChanged?(nil)
        if isVisible { layout(animated: true) }
    }

    // MARK: Layout

    private var targetHeight: CGFloat {
        if let h = preferences.panelHeight { return CGFloat(h) }
        return contentSize.height
    }

    private func layout(animated: Bool = false) {
        let size = CGSize(width: Theme.panelWidth, height: targetHeight)
        var origin: NSPoint
        if preferences.pinned, let saved = savedOrigin {
            // Keep the top edge where the user left it when the height changes.
            origin = NSPoint(x: saved.x, y: saved.y)
        } else if let a = lastAnchorFrame {
            origin = NSPoint(x: a.midX - size.width / 2, y: a.minY - size.height - 6)
        } else {
            origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - size.height)
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(lastAnchorFrame?.origin ?? origin) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            origin.x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
            origin.y = min(max(origin.y, v.minY + 8), v.maxY - size.height - 8)
        }
        programmaticResize = true
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: animated && isVisible)
        programmaticResize = false
        window.invalidateShadow()
    }

    private func userResized() {
        guard !programmaticResize else { return }
        let h = window.frame.height
        preferences.panelHeight = Double(h)
        onManualHeightChanged?(h)
        if preferences.pinned { persistOrigin() }
    }

    /// Stretchable rounded-rect mask rasterized at the screen's scale with antialiasing, so the corners stay smooth.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 2
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let px = Int((side * scale).rounded(.up))
        let image = NSImage(size: NSSize(width: side, height: side))
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            rep.size = NSSize(width: side, height: side)
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                ctx.shouldAntialias = true
                ctx.imageInterpolation = .high
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: side, height: side), xRadius: radius, yRadius: radius).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    var maxListHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return screen * 0.7 - 120
    }

    private func persistOrigin() {
        guard preferences.pinned else { return }
        savedOrigin = window.frame.origin
        preferences.panelOrigin = window.frame.origin
    }

    // MARK: Click outside

    private func installMonitors() {
        guard !preferences.pinned, globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            let anchor = self.anchorWindow
            let isInside = event.window == self.window || (anchor != nil && event.window == anchor)
            if isInside { return event }
            self.hide()
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }
}
