import Foundation

public protocol SlackAPI: Sendable {
    func authTest() async throws -> SlackAuth
    func reactionsList(limit: Int) async throws -> [SlackReactionItem]
    func conversationInfo(id: String) async throws -> SlackChannel
    func userInfo(id: String) async throws -> SlackUser
    func replies(channel: String, threadTs: String, limit: Int) async throws -> [SlackMessage]
}

public struct SlackClient: SlackAPI {
    private let token: String
    private let session: URLSession
    private static let base = URL(string: "https://slack.com/api/")!

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public func authTest() async throws -> SlackAuth {
        try await call("auth.test", query: [:], as: SlackAuth.self)
    }

    public func reactionsList(limit: Int) async throws -> [SlackReactionItem] {
        struct R: Decodable { let items: [SlackReactionItem] }
        return try await call("reactions.list", query: ["limit": String(limit), "full": "true"], as: R.self).items
    }

    public func conversationInfo(id: String) async throws -> SlackChannel {
        struct R: Decodable { let channel: SlackChannel }
        return try await call("conversations.info", query: ["channel": id], as: R.self).channel
    }

    public func userInfo(id: String) async throws -> SlackUser {
        struct R: Decodable { let user: SlackUser }
        return try await call("users.info", query: ["user": id], as: R.self).user
    }

    public func replies(channel: String, threadTs: String, limit: Int) async throws -> [SlackMessage] {
        struct R: Decodable { let messages: [SlackMessage] }
        return try await call("conversations.replies", query: ["channel": channel, "ts": threadTs, "limit": String(limit)], as: R.self).messages
    }

    // MARK: -

    private struct Envelope: Decodable { let ok: Bool; let error: String? }

    private func call<T: Decodable>(_ method: String, query: [String: String], as: T.Type) async throws -> T {
        var comps = URLComponents(url: Self.base.appendingPathComponent(method), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw SlackError.transport(error.localizedDescription) }

        guard let http = response as? HTTPURLResponse else { throw SlackError.transport("no http response") }
        if http.statusCode == 429 {
            let retry = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 30
            throw SlackError.rateLimited(retryAfter: retry)
        }
        guard (200..<300).contains(http.statusCode) else { throw SlackError.http(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) }
        catch { throw SlackError.decoding(error.localizedDescription) }
        guard envelope.ok else { throw SlackError.api(envelope.error ?? "unknown_error") }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw SlackError.decoding("\(method): \(error)") }
    }
}
