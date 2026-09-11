import XCTest
@testable import StasksCore

final class ToolLocatorTests: XCTestCase {
    func testReturnsFirstExecutableMatchInOrder() {
        let found = ToolLocator.locate("jq", directories: ["/nope", "/opt/homebrew/bin", "/usr/bin"]) { $0 == "/opt/homebrew/bin/jq" || $0 == "/usr/bin/jq" }
        XCTAssertEqual(found, "/opt/homebrew/bin/jq")
    }

    func testExpandsTilde() {
        var asked: [String] = []
        _ = ToolLocator.locate("claude", directories: ["~/.local/bin"]) { asked.append($0); return false }
        XCTAssertEqual(asked, [NSHomeDirectory() + "/.local/bin/claude"])
    }

    func testNilWhenNothingExecutable() {
        XCTAssertNil(ToolLocator.locate("x", directories: ["/a", "/b"]) { _ in false })
    }
}
