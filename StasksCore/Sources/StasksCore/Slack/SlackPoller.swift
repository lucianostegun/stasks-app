import Foundation
import Observation

public protocol TitleGenerating: Sendable {
    func title(channel: String, author: String, text: String, thread: [(author: String, text: String)]) async -> String?
}

public enum SlackConnectionState: Equatable, Sendable {
    case idle
    case connected
    case disconnected(String)
}

@MainActor
@Observable
public final class SlackPoller {
    public private(set) var connectionState: SlackConnectionState = .idle
    public private(set) var currentDelay: TimeInterval
    public var interval: TimeInterval { didSet { if !backingOff { currentDelay = interval } } }

    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private let stateURL: URL
    @ObservationIgnored private let clientProvider: @Sendable () -> (any SlackAPI)?
    @ObservationIgnored private let titleGenerator: (any TitleGenerating)?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var backingOff = false
    @ObservationIgnored private var authFailed = false
    @ObservationIgnored private var isPolling = false
    @ObservationIgnored private var identity: SlackAuth?
    @ObservationIgnored private var channelCache: [String: (SlackChannel, Date)] = [:]
    @ObservationIgnored private var userCache: [String: (SlackUser, Date)] = [:]
    @ObservationIgnored private let cacheTTL: TimeInterval = 3600
    @ObservationIgnored private let maxDelay: TimeInterval = 300
    @ObservationIgnored public var threadContextLimit = 15

    public init(store: TaskStore, stateURL: URL, clientProvider: @escaping @Sendable () -> (any SlackAPI)?,
                titleGenerator: (any TitleGenerating)?, interval: TimeInterval = 15,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.stateURL = stateURL
        self.clientProvider = clientProvider
        self.titleGenerator = titleGenerator
        self.interval = interval
        self.currentDelay = interval
        self.now = now
    }

    // MARK: Lifecycle

    public func start() {
        stop()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.paused { await self.pollOnce() }
                let delay = self.currentDelay
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    public func stop() { loop?.cancel(); loop = nil }
    public func pause() { paused = true }
    public func resume() { paused = false }

    public func reauthenticate() {
        authFailed = false
        identity = nil
        connectionState = .idle
        backingOff = false
        currentDelay = interval
    }

    // MARK: Poll

    public func pollOnce() async {
        guard let client = clientProvider() else { connectionState = .idle; return }
        if authFailed { return }
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        do {
            let auth = try await ensureIdentity(client)
            var state = AppState.load(from: stateURL, now: now())
            state.slackTeamId = auth.teamId
            state.slackUserId = auth.userId

            let items = try await client.reactionsList(limit: 50)
            let cutoff = state.installedAt.addingTimeInterval(-24 * 3600)
            let events = SlackReactionMapper.events(items: items, selfUserId: auth.userId, cutoff: cutoff) { [store] channel, ts in
                store.task(slackChannelId: channel, ts: ts)?.status
            }

            for event in events {
                switch event {
                case let .complete(channelId, ts):
                    if let t = store.task(slackChannelId: channelId, ts: ts) { store.setStatus(id: t.id, .done) }
                case let .create(channelId, message):
                    await createTask(client: client, auth: auth, channelId: channelId, message: message)
                    if (state.slackLastSeenTs[channelId] ?? "") < message.ts { state.slackLastSeenTs[channelId] = message.ts }
                }
            }

            try? state.save(to: stateURL)
            connectionState = .connected
            backingOff = false
            currentDelay = interval
        } catch let error as SlackError {
            handle(error)
        } catch {
            handle(.transport(error.localizedDescription))
        }
    }

    private func ensureIdentity(_ client: any SlackAPI) async throws -> SlackAuth {
        if let identity { return identity }
        let auth = try await client.authTest()
        identity = auth
        return auth
    }

    private func createTask(client: any SlackAPI, auth: SlackAuth, channelId: String, message: SlackMessage) async {
        let channel = await cachedChannel(client, id: channelId)
        let authorName: String
        if let uid = message.user { authorName = await cachedUser(client, id: uid)?.bestName ?? uid } else { authorName = "?" }
        let channelName = channel?.name ?? channelId
        let isDM = channel?.isDirect ?? channelId.hasPrefix("D")
        let text = message.text ?? ""

        let task = TaskItem.slack(teamId: auth.teamId, channelId: channelId, channelName: channelName, ts: message.ts,
                                  permalink: message.permalink ?? "", text: text, author: authorName, isDM: isDM, now: now())
        store.add(task)
        Log.slack.info("created task for \(channelId, privacy: .public):\(message.ts, privacy: .public)")

        guard let titleGenerator else { return }
        var thread: [(author: String, text: String)] = []
        if let threadTs = message.threadTs, let replies = try? await client.replies(channel: channelId, threadTs: threadTs, limit: threadContextLimit) {
            for r in replies where r.ts != message.ts {
                let name = r.user.flatMap { userCache[$0]?.0.bestName } ?? r.user ?? "?"
                thread.append((author: name, text: r.text ?? ""))
            }
        }
        if let generated = await titleGenerator.title(channel: channelName, author: authorName, text: text, thread: thread) {
            if let current = store.task(id: task.id), !current.isPinnedTitle {
                store.setTitle(id: task.id, generated, pinned: false)
            }
        }
    }

    private func cachedChannel(_ client: any SlackAPI, id: String) async -> SlackChannel? {
        if let (c, at) = channelCache[id], now().timeIntervalSince(at) < cacheTTL { return c }
        guard let c = try? await client.conversationInfo(id: id) else { return nil }
        channelCache[id] = (c, now())
        return c
    }

    private func cachedUser(_ client: any SlackAPI, id: String) async -> SlackUser? {
        if let (u, at) = userCache[id], now().timeIntervalSince(at) < cacheTTL { return u }
        guard let u = try? await client.userInfo(id: id) else { return nil }
        userCache[id] = (u, now())
        return u
    }

    private func handle(_ error: SlackError) {
        switch error {
        case .rateLimited(let retryAfter):
            backingOff = true
            currentDelay = min(max(retryAfter, currentDelay * 2), maxDelay)
            connectionState = .disconnected("ratelimited")
        case .api(let code) where error.isAuthFailure:
            authFailed = true
            connectionState = .disconnected(code)
        case .api(let code):
            backOff(); connectionState = .disconnected(code)
        case .http(let status):
            backOff(); connectionState = .disconnected("http \(status)")
        case .transport(let msg), .decoding(let msg):
            backOff(); connectionState = .disconnected(msg)
        }
        Log.slack.error("poll failed: \(String(describing: error), privacy: .public)")
    }

    private func backOff() {
        backingOff = true
        currentDelay = min(currentDelay * 2, maxDelay)
    }
}
