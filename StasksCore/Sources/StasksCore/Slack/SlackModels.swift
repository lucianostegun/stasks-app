import Foundation

public struct SlackReaction: Decodable, Equatable, Sendable {
    public let name: String
    public let users: [String]
    public let count: Int
}

public struct SlackMessage: Decodable, Equatable, Sendable {
    public let user: String?
    public let text: String?
    public let ts: String
    public let threadTs: String?
    public let reactions: [SlackReaction]?
    public let permalink: String?
}

public struct SlackReactionItem: Decodable, Equatable, Sendable {
    public let type: String
    public let channel: String?
    public let message: SlackMessage?
}

public struct SlackChannel: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let isIm: Bool?
    public let isMpim: Bool?
    public var isDirect: Bool { (isIm ?? false) || (isMpim ?? false) }
}

public struct SlackUser: Decodable, Equatable, Sendable {
    public struct Profile: Decodable, Equatable, Sendable { public let displayName: String? }
    public let id: String
    public let name: String
    public let realName: String?
    public let profile: Profile?
    public var bestName: String {
        if let d = profile?.displayName, !d.isEmpty { return d }
        if let r = realName, !r.isEmpty { return r }
        return name
    }
}

public struct SlackAuth: Decodable, Equatable, Sendable {
    public let url: String
    public let team: String
    public let user: String
    public let teamId: String
    public let userId: String
}

public enum SlackError: Error, Equatable, Sendable {
    case api(String)
    case http(Int)
    case rateLimited(retryAfter: TimeInterval)
    case transport(String)
    case decoding(String)

    /// Auth-class errors stop polling until the token changes.
    public var isAuthFailure: Bool {
        if case let .api(code) = self {
            return ["invalid_auth", "token_revoked", "token_expired", "account_inactive", "missing_scope", "not_authed"].contains(code)
        }
        return false
    }
}
