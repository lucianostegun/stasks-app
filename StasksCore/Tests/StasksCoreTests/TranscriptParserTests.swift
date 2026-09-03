import XCTest
@testable import StasksCore

final class TranscriptParserTests: XCTestCase {
    func testExtractsCustomTitle() {
        let line = #"{"type":"custom-title","customTitle":"SO-89165 Log violation","sessionId":"8f3c"}"#
        XCTAssertEqual(TranscriptParser.customTitle(line: line), "SO-89165 Log violation")
    }

    func testIgnoresOtherTypes() {
        XCTAssertNil(TranscriptParser.customTitle(line: #"{"type":"user","message":{"role":"user","content":"custom-title"}}"#))
        XCTAssertNil(TranscriptParser.customTitle(line: "not json"))
    }

    func testLatestWins() {
        let data = """
        {"type":"user","message":{}}
        {"type":"custom-title","customTitle":"First","sessionId":"x"}
        {"type":"assistant","message":{}}
        {"type":"custom-title","customTitle":"Second","sessionId":"x"}
        """.data(using: .utf8)!
        XCTAssertEqual(TranscriptParser.latestCustomTitle(in: data), "Second")
    }

    func testWatcherFiresOnAppendedTitle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s.jsonl")
        try "{\"type\":\"user\"}\n".write(to: file, atomically: true, encoding: .utf8)

        let exp = expectation(description: "title")
        let got = ThreadSafeBox<[String]>([])
        let w = TranscriptWatcher { session, title in
            got.value.append("\(session)=\(title)")
            exp.fulfill()
        }
        w.watch(sessionId: "S1", path: file.path)
        defer { w.unwatchAll() }

        let h = try FileHandle(forWritingTo: file)
        try h.seekToEnd()
        try h.write(contentsOf: "{\"type\":\"custom-title\",\"customTitle\":\"Renamed\",\"sessionId\":\"S1\"}\n".data(using: .utf8)!)
        try h.close()

        wait(for: [exp], timeout: 5)
        XCTAssertEqual(got.value, ["S1=Renamed"])
    }
}
