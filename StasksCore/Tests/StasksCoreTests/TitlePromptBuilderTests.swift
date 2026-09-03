import XCTest
@testable import StasksCore

final class TitlePromptBuilderTests: XCTestCase {
    func testUserPromptIncludesContext() {
        let p = TitlePromptBuilder.user(channel: "eng-backend", author: "Ana", text: "Can you review PR 42?", thread: [(author: "Bob", text: "root msg")])
        XCTAssertTrue(p.contains("Channel: #eng-backend"))
        XCTAssertTrue(p.contains("Author: Ana"))
        XCTAssertTrue(p.contains("Can you review PR 42?"))
        XCTAssertTrue(p.contains("Bob: root msg"))
    }

    func testThreadIsCappedAt15() {
        let thread = (0..<40).map { (author: "u\($0)", text: "m\($0)") }
        let p = TitlePromptBuilder.user(channel: "c", author: "a", text: "t", thread: thread)
        XCTAssertTrue(p.contains("u39: m39")); XCTAssertTrue(p.contains("u25: m25")); XCTAssertFalse(p.contains("u24: m24"))
    }

    func testNoThreadSection() {
        XCTAssertFalse(TitlePromptBuilder.user(channel: "c", author: "a", text: "t", thread: []).contains("Thread"))
    }

    func testCleanStripsQuotesPeriodAndTruncates() {
        XCTAssertEqual(TitlePromptBuilder.clean("\"Revisar PR 42.\"\n"), "Revisar PR 42")
        XCTAssertEqual(TitlePromptBuilder.clean(String(repeating: "x", count: 90)).count, 80)
        XCTAssertEqual(TitlePromptBuilder.clean("Título: Fazer X"), "Fazer X")
    }
}
