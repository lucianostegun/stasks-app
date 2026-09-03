import XCTest
@testable import StasksCore

final class SlackClientTests: XCTestCase {
    override func setUp() { MockURLProtocol.requests = [] }

    func client() -> SlackClient { SlackClient(token: "xoxp-test", session: MockURLProtocol.session()) }

    func testAuthTestSendsBearerAndDecodes() async throws {
        MockURLProtocol.handler = MockURLProtocol.respond(json: Fixtures.authTest)
        let auth = try await client().authTest()
        XCTAssertEqual(auth.userId, "UME")
        XCTAssertEqual(auth.teamId, "T1")
        let req = MockURLProtocol.requests.first!
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer xoxp-test")
        XCTAssertEqual(req.url?.host, "slack.com")
        XCTAssertEqual(req.url?.path, "/api/auth.test")
    }

    func testReactionsListQueryAndDecoding() async throws {
        MockURLProtocol.handler = MockURLProtocol.respond(json: Fixtures.reactionsList)
        let items = try await client().reactionsList(limit: 50)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0].message?.reactions?.first?.name, "eyes")
        XCTAssertEqual(items[2].message?.threadTs, "1788299000.000000")
        let q = MockURLProtocol.requests.first!.url!.query ?? ""
        XCTAssertTrue(q.contains("limit=50")); XCTAssertTrue(q.contains("full=true"))
    }

    func testApiErrorSurfaces() async {
        MockURLProtocol.handler = MockURLProtocol.respond(json: Fixtures.apiError)
        do { _ = try await client().authTest(); XCTFail("expected error") }
        catch let e as SlackError { XCTAssertEqual(e, .api("invalid_auth")) }
        catch { XCTFail("wrong error \(error)") }
    }

    func testRateLimited() async {
        MockURLProtocol.handler = MockURLProtocol.respond(429, json: "{}", headers: ["Retry-After": "30"])
        do { _ = try await client().reactionsList(limit: 50); XCTFail("expected error") }
        catch let e as SlackError { XCTAssertEqual(e, .rateLimited(retryAfter: 30)) }
        catch { XCTFail("wrong error \(error)") }
    }

    func testChannelUserReplies() async throws {
        MockURLProtocol.handler = MockURLProtocol.respond(json: Fixtures.channelInfo)
        let channel = try await client().conversationInfo(id: "C1")
        XCTAssertEqual(channel.name, "eng-backend")
        MockURLProtocol.handler = MockURLProtocol.respond(json: Fixtures.dmInfo)
        let dm = try await client().conversationInfo(id: "D1")
        XCTAssertEqual(dm.isIm, true)
        MockURLProtocol.handler = MockURLProtocol.respond(json: Fixtures.userInfo)
        let user = try await client().userInfo(id: "UANA")
        XCTAssertEqual(user.bestName, "Ana")
        MockURLProtocol.handler = MockURLProtocol.respond(json: Fixtures.replies)
        let msgs = try await client().replies(channel: "C1", threadTs: "1.0", limit: 15)
        XCTAssertEqual(msgs.count, 2)
    }
}
