import AppKit
import StasksCore

enum TerminalFocuser {
    /// Brings the session's terminal to the front. Falls back to opening `fallbackPath` in Finder when the
    /// terminal is unknown or the scripted focus fails.
    static func focus(terminal: TerminalRef?, fallbackPath: String) {
        switch TerminalTarget.resolve(terminal) {
        case let .itermSession(uuid):
            if focusITerm(uuid: uuid) { return }
        case let .terminalTab(tty):
            if focusAppleTerminal(tty: tty) { return }
        case let .activate(bundleId):
            if activate(bundleId: bundleId) { return }
        case .none:
            break
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: fallbackPath))
    }

    static func focusITerm(uuid: String) -> Bool {
        // The UUID is interpolated into an AppleScript string literal, so allow only hex digits and dashes.
        guard !uuid.isEmpty, uuid.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return false }
        return run(script: """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is "\(uuid)" then
                            select s
                            select t
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """, label: "iTerm")
    }

    static func focusAppleTerminal(tty: String) -> Bool {
        // `tty` looks like "/dev/ttys004". Restrict to that shape before interpolating into the script.
        guard tty.hasPrefix("/dev/tty"), tty.dropFirst(8).allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        return run(script: """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """, label: "Terminal")
    }

    static func activate(bundleId: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return false }
        return app.activate()
    }

    private static func run(script: String, label: String) -> Bool {
        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else { return false }
        let result = apple.executeAndReturnError(&error)
        if let error { Log.ui.error("\(label, privacy: .public) focus failed: \(error, privacy: .public)"); return false }
        return result.booleanValue
    }
}
