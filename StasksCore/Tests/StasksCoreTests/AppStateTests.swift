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
}
