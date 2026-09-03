import XCTest
@testable import StasksCore

final class SlackReactionMapperTests: XCTestCase {
    func items() throws -> [SlackReactionItem] {
        struct Envelope: Decodable { let items: [SlackReactionItem] }
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(Envelope.self, from: Data(Fixtures.reactionsList.utf8)).items
    }

    func testCreatesForOwnEyesAndIgnoresOthersAndNonMessages() throws {
        let events = SlackReactionMapper.events(items: try items(), selfUserId: "UME", cutoff: .distantPast) { _, _ in nil }
        XCTAssertEqual(events.count, 2)
        guard case let .create(channel, msg) = events[0] else { return XCTFail() }
        XCTAssertEqual(channel, "C1"); XCTAssertEqual(msg.ts, "1788300000.000100")
        // second item: eyes + check by me, no existing task -> create (the check completes on a later poll once it exists)
        guard case .create = events[1] else { return XCTFail() }
    }

    func testCompletesExistingActiveTaskWithCheckOrVerify() throws {
        let events = SlackReactionMapper.events(items: try items(), selfUserId: "UME", cutoff: .distantPast) { channel, ts in
            ts == "1788200000.000200" ? .open : nil
        }
        XCTAssertTrue(events.contains(.complete(channelId: "C1", ts: "1788200000.000200")))
        XCTAssertFalse(events.contains { if case .create(_, let m) = $0 { return m.ts == "1788200000.000200" }; return false })
    }

    func testAlreadyDoneTaskYieldsNothing() throws {
        let events = SlackReactionMapper.events(items: try items(), selfUserId: "UME", cutoff: .distantPast) { _, ts in
            ts == "1788200000.000200" ? .done : nil
        }
        XCTAssertFalse(events.contains { if case .complete(_, let ts) = $0 { return ts == "1788200000.000200" }; return false })
    }

    func testExistingOpenTaskWithOnlyEyesIsNotRecreated() throws {
        let events = SlackReactionMapper.events(items: try items(), selfUserId: "UME", cutoff: .distantPast) { _, ts in
            ts == "1788300000.000100" ? .open : nil
        }
        XCTAssertFalse(events.contains { if case .create(_, let m) = $0 { return m.ts == "1788300000.000100" }; return false })
    }

    func testCutoffFiltersOldMessages() throws {
        let cutoff = Date(timeIntervalSince1970: 1788250000)
        let events = SlackReactionMapper.events(items: try items(), selfUserId: "UME", cutoff: cutoff) { _, _ in nil }
        XCTAssertEqual(events.count, 1)
    }

    func testVerifyEmojiCounts() throws {
        let json = #"[{"type":"message","channel":"C9","message":{"ts":"5.0","text":"x","reactions":[{"name":"verify","users":["UME"],"count":1}]}}]"#
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        let items = try d.decode([SlackReactionItem].self, from: Data(json.utf8))
        let events = SlackReactionMapper.events(items: items, selfUserId: "UME", cutoff: .distantPast) { _, _ in .inProgress }
        XCTAssertEqual(events, [.complete(channelId: "C9", ts: "5.0")])
    }

    func testTsToDate() {
        XCTAssertEqual(SlackReactionMapper.date(fromTs: "1788300000.000100")?.timeIntervalSince1970 ?? 0, 1788300000, accuracy: 0.001)
        XCTAssertNil(SlackReactionMapper.date(fromTs: "abc"))
    }
}
