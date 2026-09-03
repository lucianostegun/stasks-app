import XCTest
@testable import StasksCore

final class InboxDrainerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("stasks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func append(_ line: String, to name: String = "inbox.jsonl") throws {
        let url = dir.appendingPathComponent(name)
        let handle: FileHandle
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: (line + "\n").data(using: .utf8)!)
        try handle.close()
    }

    func testDrainNowParsesAndRemovesInbox() throws {
        try append(#"{"event":"SessionEnd","session_id":"S1"}"#)
        try append("garbage")
        let received = ThreadSafeBox<[InboxEvent]>([])
        let d = InboxDrainer(directory: dir, settleDelay: 0) { received.value.append(contentsOf: $0) }
        d.drainNow()
        XCTAssertEqual(received.value.map(\.sessionId), ["S1"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("inbox.jsonl").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(leftovers.isEmpty, "\(leftovers)")
    }

    func testDrainNowPicksUpLeftoverProcessingFiles() throws {
        try append(#"{"event":"SessionEnd","session_id":"OLD"}"#, to: "inbox.processing-abc.jsonl")
        let received = ThreadSafeBox<[InboxEvent]>([])
        InboxDrainer(directory: dir, settleDelay: 0) { received.value.append(contentsOf: $0) }.drainNow()
        XCTAssertEqual(received.value.map(\.sessionId), ["OLD"])
    }

    func testDrainNowWithNoInboxIsNoop() {
        let received = ThreadSafeBox<[InboxEvent]>([])
        InboxDrainer(directory: dir, settleDelay: 0) { received.value.append(contentsOf: $0) }.drainNow()
        XCTAssertTrue(received.value.isEmpty)
    }

    func testDrainNowKeepsUnreadableProcessingFileForRetry() throws {
        try XCTSkipIf(getuid() == 0, "root can read mode-000 files, so this test cannot exercise the failure path")
        let name = "inbox.processing-x.jsonl"
        try append(#"{"event":"SessionEnd","session_id":"UNREADABLE"}"#, to: name)
        let url = dir.appendingPathComponent(name)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }

        let received = ThreadSafeBox<[InboxEvent]>([])
        InboxDrainer(directory: dir, settleDelay: 0) { received.value.append(contentsOf: $0) }.drainNow()

        XCTAssertTrue(received.value.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testWatcherDrainsAfterAppend() throws {
        let exp = expectation(description: "drained")
        let received = ThreadSafeBox<[InboxEvent]>([])
        let d = InboxDrainer(directory: dir, settleDelay: 0) { events in
            received.value.append(contentsOf: events)
            if !events.isEmpty { exp.fulfill() }
        }
        d.start()
        defer { d.stop() }
        try append(#"{"event":"SessionEnd","session_id":"W1"}"#)
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(received.value.map(\.sessionId), ["W1"])
    }
}

final class ThreadSafeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ v: T) { _value = v }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
