import XCTest
@testable import StasksCore

final class RelativeTimeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func t(_ secondsAgo: TimeInterval) -> String { RelativeTime.label(from: now.addingTimeInterval(-secondsAgo), to: now) }
    func testLabels() {
        XCTAssertEqual(t(0), "now"); XCTAssertEqual(t(59), "now")
        XCTAssertEqual(t(60), "1m"); XCTAssertEqual(t(12 * 60), "12m")
        XCTAssertEqual(t(3600), "1h"); XCTAssertEqual(t(2 * 3600 + 100), "2h")
        XCTAssertEqual(t(86_400), "1d"); XCTAssertEqual(t(3 * 86_400), "3d")
        XCTAssertEqual(t(-30), "now")
    }
    func testNowLabelIsInjectable() {
        XCTAssertEqual(RelativeTime.label(from: now, to: now, nowLabel: "agora"), "agora")
        XCTAssertEqual(RelativeTime.label(from: now.addingTimeInterval(-120), to: now, nowLabel: "agora"), "2m")
    }
}
