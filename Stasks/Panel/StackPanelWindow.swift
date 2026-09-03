import AppKit

final class StackPanelWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
        minSize = NSSize(width: 340, height: 160)
        maxSize = NSSize(width: 340, height: 4000)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    var onEscape: (() -> Void)?
}
