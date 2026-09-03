import XCTest
@testable import StasksCore

final class SlackTextTests: XCTestCase {
    func testLinksBecomeLabelOrTarget() {
        XCTAssertEqual(SlackText.plain("PR <https://github.com/x/y/pull/1|github.com/x/y/pull/1> ready"), "PR github.com/x/y/pull/1 ready")
        XCTAssertEqual(SlackText.plain("see <https://example.com>"), "see https://example.com")
        XCTAssertEqual(SlackText.plain("mail <mailto:a@b.com|a@b.com>"), "mail a@b.com")
    }

    func testMentionsResolveThroughMap() {
        XCTAssertEqual(SlackText.plain("<@U1> can you check?", users: ["U1": "Ana"]), "@Ana can you check?")
        XCTAssertEqual(SlackText.plain("<@U1> hi"), "@U1 hi")
        XCTAssertEqual(SlackText.plain("<@U1|ana> hi"), "@ana hi")
        XCTAssertEqual(SlackText.mentionedUserIds("<@U1> and <@W22|x> and <#C3|general>"), ["U1", "W22"])
    }

    func testChannelsAndSpecials() {
        XCTAssertEqual(SlackText.plain("in <#C1|eng-backend> please"), "in #eng-backend please")
        XCTAssertEqual(SlackText.plain("<!here> deploy done"), "@here deploy done")
        XCTAssertEqual(SlackText.plain("<!subteam^S1|@turtles> fyi"), "@turtles fyi")
    }

    func testEntitiesAndPlainTextUntouched() {
        XCTAssertEqual(SlackText.plain("a &amp; b &lt; c"), "a & b < c")
        XCTAssertEqual(SlackText.plain("nothing special here"), "nothing special here")
    }
}
