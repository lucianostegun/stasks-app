import AppKit
import StasksCore

enum TerminalFocuser {
    /// `ITERM_SESSION_ID` looks like `w0t3p1:651EB773-...`. iTerm2's AppleScript `unique id` is the UUID part.
    static func uuid(from itermSessionId: String) -> String {
        itermSessionId.split(separator: ":").last.map(String.init) ?? itermSessionId
    }

    static func focus(itermSessionId: String?, fallbackPath: String) {
        if let id = itermSessionId, focusITerm(uuid: uuid(from: id)) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: fallbackPath))
    }

    static func focusITerm(uuid: String) -> Bool {
        // The UUID is interpolated into an AppleScript string literal, so allow only hex digits and dashes.
        guard !uuid.isEmpty, uuid.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return false }
        let script = """
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
        """
        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else { return false }
        let result = apple.executeAndReturnError(&error)
        if let error { Log.ui.error("iTerm focus failed: \(error, privacy: .public)"); return false }
        return result.booleanValue
    }
}
