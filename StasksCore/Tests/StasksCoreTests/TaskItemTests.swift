import XCTest
@testable import StasksCore

final class TaskItemTests: XCTestCase {
    func testStatusRawValues() {
        XCTAssertEqual(TaskStatus.inProgress.rawValue, "inProgress")
    }
}
