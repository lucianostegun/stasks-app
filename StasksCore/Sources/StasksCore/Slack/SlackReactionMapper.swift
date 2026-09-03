import Foundation

public enum SlackReactionEvent: Equatable, Sendable {
    case create(channelId: String, message: SlackMessage)
    case complete(channelId: String, ts: String)
}

public enum SlackReactionMapper {
    public static let openEmoji: Set<String> = ["eyes"]
    public static let doneEmoji: Set<String> = ["white_check_mark", "verify"]

    public static func date(fromTs ts: String) -> Date? {
        guard let seconds = Double(ts) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public static func events(items: [SlackReactionItem], selfUserId: String, cutoff: Date,
                              existingStatus: (_ channelId: String, _ ts: String) -> TaskStatus?) -> [SlackReactionEvent] {
        var out: [SlackReactionEvent] = []
        for item in items {
            guard item.type == "message", let channel = item.channel, let message = item.message else { continue }
            guard let when = date(fromTs: message.ts), when >= cutoff else { continue }
            let mine = Set((message.reactions ?? []).filter { $0.users.contains(selfUserId) }.map(\.name))
            let hasOpen = !mine.isDisjoint(with: openEmoji)
            let hasDone = !mine.isDisjoint(with: doneEmoji)
            let status = existingStatus(channel, message.ts)

            switch (status, hasOpen, hasDone) {
            case (nil, true, _):
                out.append(.create(channelId: channel, message: message))
            case (.some(let s), _, true) where s.isActive:
                out.append(.complete(channelId: channel, ts: message.ts))
            default:
                continue
            }
        }
        return out
    }
}
