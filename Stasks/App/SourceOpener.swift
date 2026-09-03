import AppKit
import StasksCore

enum SourceOpener {
    static func open(_ task: TaskItem) {
        switch task.source {
        case let .claude(_, _, cwd, itermSessionId):
            TerminalFocuser.focus(itermSessionId: itermSessionId, fallbackPath: cwd)
        case let .slack(teamId, channelId, _, ts, permalink):
            let deep = URL(string: "slack://channel?team=\(teamId)&id=\(channelId)&message=\(ts)")
            if let deep, NSWorkspace.shared.urlForApplication(toOpen: deep) != nil {
                NSWorkspace.shared.open(deep)
            } else if let url = URL(string: permalink), !permalink.isEmpty {
                NSWorkspace.shared.open(url)
            }
        case .manual:
            break
        }
    }
}
