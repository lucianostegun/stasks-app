import XCTest
@testable import StasksCore

final class InboxParserTests: XCTestCase {
    func testParsesSessionStart() {
        let line = #"{"event":"SessionStart","session_id":"S1","cwd":"/p","transcript_path":"/t","source":"startup","prompt":null,"reason":null,"iterm_session_id":"w0:X","term_program":"iTerm.app","ts":1788377555}"#
        let e = InboxParser.parse(line: line)
        XCTAssertEqual(e?.event, .sessionStart)
        XCTAssertEqual(e?.sessionId, "S1")
        XCTAssertEqual(e?.cwd, "/p")
        XCTAssertEqual(e?.itermSessionId, "w0:X")
        XCTAssertEqual(e?.ts, 1788377555)
    }

    func testUnknownEventIsIgnored() {
        XCTAssertNil(InboxParser.parse(line: #"{"event":"PreToolUse","session_id":"S1"}"#))
    }

    func testMalformedLinesAreSkipped() {
        let data = """
        garbage
        {"event":"SessionEnd","session_id":"S1","reason":"exit"}

        {"event":"UserPromptSubmit","session_id":"S1","prompt":"hi"}
        """.data(using: .utf8)!
        let events = InboxParser.parse(data: data)
        XCTAssertEqual(events.map(\.event), [.sessionEnd, .userPromptSubmit])
    }
}
