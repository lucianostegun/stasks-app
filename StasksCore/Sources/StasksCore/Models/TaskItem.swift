import Foundation

public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case open, inProgress, done
    public var isActive: Bool { self != .done }
}

public enum StackOrder: String, Codable, Sendable, CaseIterable {
    case lifo, fifo
}

/// What a Claude Code session is doing right now, driven by the UserPromptSubmit, Stop and Notification hooks.
public enum ClaudeActivity: String, Codable, Sendable {
    case working        // user sent a prompt, Claude is answering
    case waitingInput   // Claude asked for permission or input
    case finished       // Claude finished its answer and is idle
}

public enum TaskSourceKind: String, Codable, Sendable {
    case claude, slack, manual
}

public enum TaskSource: Codable, Equatable, Sendable {
    case claude(sessionId: String, transcriptPath: String, cwd: String, itermSessionId: String?)
    case slack(teamId: String, channelId: String, channelName: String, ts: String, permalink: String)
    case manual

    public var kind: TaskSourceKind {
        switch self {
        case .claude: return .claude
        case .slack: return .slack
        case .manual: return .manual
        }
    }

    public var claudeSessionId: String? {
        if case let .claude(sessionId, _, _, _) = self { return sessionId }
        return nil
    }

    public var slackKey: String? {
        if case let .slack(_, channelId, _, ts, _) = self { return "\(channelId):\(ts)" }
        return nil
    }
}

public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var subtitle: String?
    public let source: TaskSource
    public var status: TaskStatus
    public let createdAt: Date
    public var completedAt: Date?
    public var isPinnedTitle: Bool
    public var isProvisionalTitle: Bool
    public var activity: ClaudeActivity?

    public init(id: UUID = UUID(), title: String, subtitle: String?, source: TaskSource, status: TaskStatus = .open,
                createdAt: Date, completedAt: Date? = nil, isPinnedTitle: Bool = false, isProvisionalTitle: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.source = source
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.isPinnedTitle = isPinnedTitle
        self.isProvisionalTitle = isProvisionalTitle
        self.activity = nil
    }

    public static let maxTitleLength = 80

    public static func truncatedTitle(_ text: String) -> String {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxTitleLength else { return trimmed }
        return String(trimmed.prefix(maxTitleLength - 1)) + "…"
    }

    public static func folderName(cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    public static func abbreviatedHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    public static func claude(sessionId: String, cwd: String, transcriptPath: String, itermSessionId: String?, now: Date) -> TaskItem {
        TaskItem(title: folderName(cwd: cwd),
                 subtitle: abbreviatedHome(cwd),
                 source: .claude(sessionId: sessionId, transcriptPath: transcriptPath, cwd: cwd, itermSessionId: itermSessionId),
                 createdAt: now)
    }

    public static func slack(teamId: String, channelId: String, channelName: String, ts: String, permalink: String,
                             text: String, author: String, isDM: Bool, now: Date) -> TaskItem {
        let subtitle = isDM ? "DM · \(author)" : "#\(channelName) · \(author)"
        return TaskItem(title: truncatedTitle(text.isEmpty ? "(no text)" : text),
                        subtitle: subtitle,
                        source: .slack(teamId: teamId, channelId: channelId, channelName: channelName, ts: ts, permalink: permalink),
                        createdAt: now,
                        isProvisionalTitle: true)
    }

    public static func manual(title: String, now: Date) -> TaskItem {
        TaskItem(title: truncatedTitle(title), subtitle: "Manual", source: .manual, createdAt: now)
    }
}
