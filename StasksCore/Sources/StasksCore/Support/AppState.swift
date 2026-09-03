import Foundation

public struct AppState: Equatable, Sendable {
    public var installedAt: Date
    public var slackLastSeenTs: [String: String] = [:]
    public var slackTeamId: String?
    public var slackUserId: String?
    public var panelOrigin: CGPoint?

    public init(installedAt: Date) { self.installedAt = installedAt }

    public static func load(from url: URL, now: Date) -> AppState {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let s = try? decoder.decode(AppState.self, from: data) { return s }
        return AppState(installedAt: now)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

extension AppState: Codable {
    private enum CodingKeys: String, CodingKey {
        case installedAt
        case slackLastSeenTs
        case slackTeamId
        case slackUserId
        case panelOriginX
        case panelOriginY
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        slackLastSeenTs = try container.decodeIfPresent([String: String].self, forKey: .slackLastSeenTs) ?? [:]
        slackTeamId = try container.decodeIfPresent(String.self, forKey: .slackTeamId)
        slackUserId = try container.decodeIfPresent(String.self, forKey: .slackUserId)

        if let x = try container.decodeIfPresent(CGFloat.self, forKey: .panelOriginX),
           let y = try container.decodeIfPresent(CGFloat.self, forKey: .panelOriginY) {
            panelOrigin = CGPoint(x: x, y: y)
        } else {
            panelOrigin = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(installedAt, forKey: .installedAt)
        try container.encode(slackLastSeenTs, forKey: .slackLastSeenTs)
        try container.encodeIfPresent(slackTeamId, forKey: .slackTeamId)
        try container.encodeIfPresent(slackUserId, forKey: .slackUserId)

        if let panelOrigin = panelOrigin {
            try container.encode(panelOrigin.x, forKey: .panelOriginX)
            try container.encode(panelOrigin.y, forKey: .panelOriginY)
        }
    }
}

extension AppState {
    public static func == (lhs: AppState, rhs: AppState) -> Bool {
        let panelOriginEqual: Bool
        switch (lhs.panelOrigin, rhs.panelOrigin) {
        case (nil, nil):
            panelOriginEqual = true
        case let (l?, r?):
            panelOriginEqual = l.x == r.x && l.y == r.y
        default:
            panelOriginEqual = false
        }

        return lhs.installedAt == rhs.installedAt &&
               lhs.slackLastSeenTs == rhs.slackLastSeenTs &&
               lhs.slackTeamId == rhs.slackTeamId &&
               lhs.slackUserId == rhs.slackUserId &&
               panelOriginEqual
    }
}
