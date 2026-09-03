import XCTest
@testable import StasksCore

@MainActor
final class SlackPollerTests: XCTestCase {
    final class FakeSlack: SlackAPI, @unchecked Sendable {
        var items: [SlackReactionItem] = []
        var authError: SlackError?
        var listError: SlackError?
        var listDelayNanos: UInt64 = 0
        var calls: [String] = []
        func authTest() async throws -> SlackAuth {
            calls.append("auth"); if let e = authError { throw e }
            return SlackAuth(url: "u", team: "SOCi", user: "me", teamId: "T1", userId: "UME")
        }
        func reactionsList(limit: Int) async throws -> [SlackReactionItem] {
            calls.append("list")
            if listDelayNanos > 0 { try? await Task.sleep(nanoseconds: listDelayNanos) }
            if let e = listError { throw e }; return items
        }
        func conversationInfo(id: String) async throws -> SlackChannel {
            calls.append("channel:\(id)")
            return id.hasPrefix("D") ? SlackChannel(id: id, name: nil, isIm: true, isMpim: false) : SlackChannel(id: id, name: "eng-backend", isIm: false, isMpim: false)
        }
        func userInfo(id: String) async throws -> SlackUser {
            calls.append("user:\(id)")
            return SlackUser(id: id, name: "ana", realName: "Ana Souza", profile: .init(displayName: "Ana"))
        }
        func replies(channel: String, threadTs: String, limit: Int) async throws -> [SlackMessage] {
            calls.append("replies")
            return [SlackMessage(user: "UBOB", text: "root", ts: threadTs, threadTs: nil, reactions: nil, permalink: nil)]
        }
    }
    final class FakeTitles: TitleGenerating, @unchecked Sendable {
        var result: String? = "LLM title"
        var received: [String] = []
        func title(channel: String, author: String, text: String, thread: [(author: String, text: String)]) async -> String? {
            received.append("\(channel)|\(author)|\(text)|\(thread.count)"); return result
        }
    }

    var store: TaskStore!; var slack: FakeSlack!; var titles: FakeTitles!; var stateURL: URL!
    let now = Date(timeIntervalSince1970: 1_788_300_500)

    override func setUp() {
        store = TaskStore(persistence: nil, now: { [now] in now })
        slack = FakeSlack(); titles = FakeTitles()
        stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/state.json")
        let s = AppState(installedAt: now); try? s.save(to: stateURL)
    }

    func poller() -> SlackPoller {
        SlackPoller(store: store, stateURL: stateURL, clientProvider: { [slack] in slack }, titleGenerator: titles, now: { [now] in now })
    }

    func items(_ json: String) -> [SlackReactionItem] {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        return try! d.decode([SlackReactionItem].self, from: Data(json.utf8))
    }

    func testCreatesTaskWithProvisionalThenLLMTitle() async {
        slack.items = items(#"[{"type":"message","channel":"C1","message":{"user":"UANA","text":"Please review the PR\nthx","ts":"1788300000.1","thread_ts":"1788299000.0","reactions":[{"name":"eyes","users":["UME"],"count":1}],"permalink":"https://p"}}]"#)
        let p = poller()
        await p.pollOnce()
        let t = store.task(slackChannelId: "C1", ts: "1788300000.1")
        XCTAssertNotNil(t)
        XCTAssertEqual(t?.subtitle, "#eng-backend · Ana")
        XCTAssertEqual(p.connectionState, .connected)
        if case let .slack(team, _, name, _, permalink)? = t?.source { XCTAssertEqual(team, "T1"); XCTAssertEqual(name, "eng-backend"); XCTAssertEqual(permalink, "https://p") } else { XCTFail() }
        // title generation is awaited inside pollOnce for testability
        XCTAssertEqual(t?.title, "LLM title")
        XCTAssertFalse(t!.isProvisionalTitle)
        XCTAssertEqual(titles.received.first, "eng-backend|Ana|Please review the PR\nthx|1")
        XCTAssertTrue(slack.calls.contains("replies"))
    }

    func testLLMFailureKeepsProvisionalTitle() async {
        titles.result = nil
        slack.items = items(#"[{"type":"message","channel":"C1","message":{"user":"UANA","text":"Please review","ts":"1788300000.1","reactions":[{"name":"eyes","users":["UME"],"count":1}]}}]"#)
        await poller().pollOnce()
        let t = store.task(slackChannelId: "C1", ts: "1788300000.1")!
        XCTAssertEqual(t.title, "Please review"); XCTAssertTrue(t.isProvisionalTitle)
    }

    func testCompletesOnCheckmark() async {
        store.add(TaskItem.slack(teamId: "T1", channelId: "C1", channelName: "eng", ts: "1788300000.1", permalink: "", text: "x", author: "a", isDM: false, now: now))
        slack.items = items(#"[{"type":"message","channel":"C1","message":{"user":"UANA","text":"x","ts":"1788300000.1","reactions":[{"name":"eyes","users":["UME"],"count":1},{"name":"white_check_mark","users":["UME"],"count":1}]}}]"#)
        await poller().pollOnce()
        XCTAssertEqual(store.task(slackChannelId: "C1", ts: "1788300000.1")?.status, .done)
    }

    func testCutoffIsInstalledAtMinus24h() async {
        slack.items = items(#"[{"type":"message","channel":"C1","message":{"text":"old","ts":"1788200000.0","reactions":[{"name":"eyes","users":["UME"],"count":1}]}}]"#)
        await poller().pollOnce()
        XCTAssertEqual(store.tasks.count, 0)
    }

    func testAuthFailureDisconnectsAndStopsCalling() async {
        slack.authError = .api("invalid_auth")
        let p = poller()
        await p.pollOnce()
        XCTAssertEqual(p.connectionState, .disconnected("invalid_auth"))
        await p.pollOnce()
        XCTAssertEqual(slack.calls.filter { $0 == "auth" }.count, 1)
    }

    func testRateLimitBacksOffAndKeepsState() async {
        slack.listError = .rateLimited(retryAfter: 60)
        let p = poller()
        await p.pollOnce()
        XCTAssertEqual(p.connectionState, .disconnected("ratelimited"))
        XCTAssertGreaterThanOrEqual(p.currentDelay, 60)
        slack.listError = nil
        await p.pollOnce()
        XCTAssertEqual(p.connectionState, .connected)
        XCTAssertEqual(p.currentDelay, p.interval)
    }

    func testNoClientMeansIdle() async {
        let p = SlackPoller(store: store, stateURL: stateURL, clientProvider: { nil }, titleGenerator: nil)
        await p.pollOnce()
        XCTAssertEqual(p.connectionState, .idle)
    }

    func testDMSubtitle() async {
        slack.items = items(#"[{"type":"message","channel":"D1","message":{"user":"UANA","text":"hey","ts":"1788300000.1","reactions":[{"name":"eyes","users":["UME"],"count":1}]}}]"#)
        await poller().pollOnce()
        XCTAssertEqual(store.task(slackChannelId: "D1", ts: "1788300000.1")?.subtitle, "DM · Ana")
    }

    func testOverlappingPollOnceRunsOnlyOne() async {
        slack.listDelayNanos = 50_000_000
        slack.items = items(#"[{"type":"message","channel":"C1","message":{"user":"UANA","text":"hey","ts":"1788300000.1","reactions":[{"name":"eyes","users":["UME"],"count":1}]}}]"#)
        let p = poller()
        async let a: Void = p.pollOnce()
        async let b: Void = p.pollOnce()
        _ = await (a, b)
        XCTAssertEqual(slack.calls.filter { $0 == "list" }.count, 1)
        XCTAssertEqual(store.tasks.count, 1)
    }
}
