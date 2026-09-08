import Foundation

/// Where a Claude Code session is running, as captured by the hook from the environment.
/// `program` is `TERM_PROGRAM`, `itermSessionId` is `ITERM_SESSION_ID`, `tty` is the controlling terminal device.
public struct TerminalRef: Codable, Equatable, Sendable {
    public let program: String?
    public let itermSessionId: String?
    public let tty: String?

    public init(program: String?, itermSessionId: String?, tty: String?) {
        self.program = program
        self.itermSessionId = itermSessionId
        self.tty = tty
    }

    public var isEmpty: Bool { program == nil && itermSessionId == nil && tty == nil }
}

/// Decides how to bring a session's terminal to the front. Pure, so the app layer only executes.
public enum TerminalTarget: Equatable, Sendable {
    /// iTerm2: select the session whose AppleScript `unique id` is `uuid`.
    case itermSession(uuid: String)
    /// Terminal.app: select the tab whose `tty` matches.
    case terminalTab(tty: String)
    /// Terminal without a scriptable session model: just activate the app.
    case activate(bundleId: String)
    /// Nothing known about the terminal: caller falls back (e.g. open cwd in Finder).
    case none

    /// `TERM_PROGRAM` values mapped to bundle identifiers, for terminals we can only activate.
    static let bundleIds: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "vscode": "com.microsoft.VSCode",
        "Alacritty": "org.alacritty",
        "kitty": "net.kovidgoyal.kitty",
        "WezTerm": "com.github.wez.wezterm",
        "Hyper": "co.zeit.hyper",
    ]

    /// `ITERM_SESSION_ID` looks like `w0t3p1:651EB773-...`. iTerm2's AppleScript `unique id` is the UUID part.
    public static func itermUUID(from itermSessionId: String) -> String {
        itermSessionId.split(separator: ":").last.map(String.init) ?? itermSessionId
    }

    public static func resolve(_ ref: TerminalRef?) -> TerminalTarget {
        guard let ref else { return .none }
        if let id = ref.itermSessionId, !id.isEmpty { return .itermSession(uuid: itermUUID(from: id)) }
        if ref.program == "Apple_Terminal", let tty = ref.tty, !tty.isEmpty { return .terminalTab(tty: tty) }
        if let program = ref.program, let bundleId = bundleIds[program] { return .activate(bundleId: bundleId) }
        return .none
    }
}
