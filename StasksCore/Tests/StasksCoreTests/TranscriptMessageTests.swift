import XCTest
@testable import StasksCore

final class TranscriptMessageTests: XCTestCase {
    let user = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":"Fix the login bug"}}"#
    let assistantThinkingAndText = #"{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"Found it.\nThe bug is in auth.swift"}]}}"#
    let assistantToolOnly = #"{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}"#
    let userToolResult = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#
    let sidechain = #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"subagent noise"}]}}"#
    let title = #"{"type":"custom-title","customTitle":"X","sessionId":"S"}"#

    func data(_ lines: String...) -> Data { lines.joined(separator: "\n").data(using: .utf8)! }

    func testLastAssistantTextSkipsThinkingToolsAndSidechains() {
        let d = data(user, assistantThinkingAndText, assistantToolOnly, userToolResult, sidechain, title)
        XCTAssertEqual(TranscriptParser.lastAssistantText(in: d), "Found it.\nThe bug is in auth.swift")
    }

    func testNoAssistantTextReturnsNil() {
        XCTAssertNil(TranscriptParser.lastAssistantText(in: data(user, assistantToolOnly, "garbage")))
    }

    func testLatestAssistantWins() {
        let second = #"{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"Second answer"}]}}"#
        XCTAssertEqual(TranscriptParser.lastAssistantText(in: data(assistantThinkingAndText, user, second)), "Second answer")
    }

    func testWatcherReportsAssistantText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s.jsonl")
        try (user + "\n").write(to: file, atomically: true, encoding: .utf8)

        let exp = expectation(description: "message")
        let got = ThreadSafeBox<[String]>([])
        let w = TranscriptWatcher(onTitle: { _, _ in }, onMessage: { session, text in
            got.value.append("\(session)=\(text)")
            exp.fulfill()
        })
        w.watch(sessionId: "S1", path: file.path)
        defer { w.unwatchAll() }

        let h = try FileHandle(forWritingTo: file)
        try h.seekToEnd()
        try h.write(contentsOf: (assistantThinkingAndText + "\n").data(using: .utf8)!)
        try h.close()

        wait(for: [exp], timeout: 5)
        XCTAssertEqual(got.value, ["S1=Found it.\nThe bug is in auth.swift"])
    }
}
