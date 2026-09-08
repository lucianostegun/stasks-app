import XCTest
@testable import StasksCore

final class TaskItemTests: XCTestCase {
    func testClaudeFactoryDefaults() {
        let now = Date(timeIntervalSince1970: 1_000)
        let t = TaskItem.claude(sessionId: "s1", cwd: "/Users/me/Projetos/foo", transcriptPath: "/t.jsonl", terminal: TerminalRef(program: "iTerm.app", itermSessionId: "w0t1p0:ABC", tty: nil), now: now)
        XCTAssertEqual(t.title, "foo")
        XCTAssertEqual(t.subtitle, TaskItem.abbreviatedHome("/Users/me/Projetos/foo"))
        XCTAssertEqual(TaskItem.abbreviatedHome(FileManager.default.homeDirectoryForCurrentUser.path + "/x"), "~/x")
        XCTAssertEqual(t.status, .open)
        XCTAssertEqual(t.createdAt, now)
        XCTAssertFalse(t.isPinnedTitle)
        XCTAssertFalse(t.isProvisionalTitle)
        XCTAssertEqual(t.source.claudeSessionId, "s1")
        XCTAssertEqual(t.source.kind, .claude)
    }

    func testSlackFactoryIsProvisional() {
        let t = TaskItem.slack(teamId: "T1", channelId: "C1", channelName: "eng", ts: "1.2", permalink: "https://x", text: "Line one\nline two", author: "Ana", isDM: false, now: Date())
        XCTAssertEqual(t.title, "Line one")
        XCTAssertEqual(t.subtitle, "#eng · Ana")
        XCTAssertTrue(t.isProvisionalTitle)
        XCTAssertEqual(t.source.slackKey, "C1:1.2")
    }

    func testSlackDMSubtitle() {
        let t = TaskItem.slack(teamId: "T1", channelId: "D1", channelName: "", ts: "1.2", permalink: "", text: "hi", author: "Ana", isDM: true, now: Date())
        XCTAssertEqual(t.subtitle, "DM · Ana")
    }

    func testTitleTruncation() {
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(TaskItem.truncatedTitle(long).count, 80)
        XCTAssertTrue(TaskItem.truncatedTitle(long).hasSuffix("…"))
    }

    func testManualFactory() {
        let t = TaskItem.manual(title: "  Pay bills  ", now: Date())
        XCTAssertEqual(t.title, "Pay bills")
        XCTAssertEqual(t.subtitle, "Manual")
        XCTAssertEqual(t.source, .manual)
    }

    func testCodableRoundTrip() throws {
        let t = TaskItem.slack(teamId: "T", channelId: "C", channelName: "c", ts: "1.0", permalink: "p", text: "x", author: "a", isDM: false, now: Date(timeIntervalSince1970: 5))
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(TaskItem.self, from: data)
        XCTAssertEqual(back, t)
    }

    func testStatusIsActive() {
        XCTAssertTrue(TaskStatus.open.isActive)
        XCTAssertTrue(TaskStatus.inProgress.isActive)
        XCTAssertFalse(TaskStatus.done.isActive)
    }
}
