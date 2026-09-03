import XCTest
@testable import StasksCore

final class AppStateTests: XCTestCase {
    func testLoadCreatesDefaultThenRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/state.json")
        let now = Date(timeIntervalSince1970: 1_000)
        var s = AppState.load(from: url, now: now)
        XCTAssertEqual(s.installedAt, now)
        XCTAssertTrue(s.slackLastSeenTs.isEmpty)
        s.slackLastSeenTs["C1"] = "12.5"
        s.panelOrigin = CGPoint(x: 10, y: 20)
        try s.save(to: url)
        let back = AppState.load(from: url, now: Date())
        XCTAssertEqual(back, s)
    }

    func testSaveIfNewCreatesWhenAbsentAndSkipsWhenPresent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/state.json")
        let first = AppState(installedAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertTrue(first.saveIfNew(to: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let onDisk = AppState.load(from: url, now: Date())
        var second = onDisk
        second.installedAt = Date(timeIntervalSince1970: 2_000)
        XCTAssertFalse(second.saveIfNew(to: url))

        let unchanged = AppState.load(from: url, now: Date())
        XCTAssertEqual(unchanged, onDisk)
    }
}
