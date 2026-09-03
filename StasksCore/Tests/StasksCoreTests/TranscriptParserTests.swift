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

    func testWatcherRecoversAfterTruncationOrRotation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s.jsonl")
        // A deliberately long title so the stale byte offset recorded after the initial read is
        // bigger than the rotated file's single short-titled line below, forcing the size <
        // offset reset path in readNew.
        let paddedInitialTitle = String(repeating: "X", count: 300)
        try "{\"type\":\"custom-title\",\"customTitle\":\"\(paddedInitialTitle)\",\"sessionId\":\"S1\"}\n"
            .write(to: file, atomically: true, encoding: .utf8)

        // Each mutation below waits for the watcher to report the title it introduces before the
        // next mutation happens. That confirms watch()'s async initial-tail-read (and its kevent
        // arming) has actually run, and then that the delete/rename-triggered reopen from the
        // rotate has actually run, before moving on: otherwise a mutation could land in the small
        // window before the watcher's own async setup catches up, and never be observed since
        // nothing else changes the file afterward to produce a further event.
        let beforeExp = expectation(description: "before")
        let rotatedExp = expectation(description: "rotated")
        let afterExp = expectation(description: "afterRotate")
        let got = ThreadSafeBox<[String]>([])
        let w = TranscriptWatcher { session, title in
            got.value.append("\(session)=\(title)")
            if title == paddedInitialTitle { beforeExp.fulfill() }
            if title == "R" { rotatedExp.fulfill() }
            if title == "AfterRotate" { afterExp.fulfill() }
        }
        w.watch(sessionId: "S1", path: file.path)
        defer { w.unwatchAll() }

        wait(for: [beforeExp], timeout: 5)

        // Rotate: atomically replace with much shorter content, still carrying its own (much
        // shorter) title "R", so the file shrinks well below the stale offset above.
        try "{\"type\":\"custom-title\",\"customTitle\":\"R\",\"sessionId\":\"S1\"}\n"
            .write(to: file, atomically: true, encoding: .utf8)
        wait(for: [rotatedExp], timeout: 5)

        // Append a further custom-title line on the now fully re-armed watch.
        let h = try FileHandle(forWritingTo: file)
        try h.seekToEnd()
        try h.write(contentsOf: "{\"type\":\"custom-title\",\"customTitle\":\"AfterRotate\",\"sessionId\":\"S1\"}\n".data(using: .utf8)!)
        try h.close()

        wait(for: [afterExp], timeout: 5)
        XCTAssertTrue(got.value.contains("S1=AfterRotate"))
    }
}
