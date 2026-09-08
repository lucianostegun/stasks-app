import XCTest
@testable import StasksCore

final class TerminalRefTests: XCTestCase {
    func testClaudeSourceCarriesTerminal() {
        let ref = TerminalRef(program: "iTerm.app", itermSessionId: "w0t1p0:ABC", tty: "/dev/ttys001")
        let t = TaskItem.claude(sessionId: "s1", cwd: "/p", transcriptPath: "/t", terminal: ref, now: Date())
        guard case let .claude(_, _, _, terminal) = t.source else { return XCTFail("not claude") }
        XCTAssertEqual(terminal, ref)
    }

    func testLegacyStoredTaskWithoutTerminalStillDecodes() throws {
        // tasks.json written before TerminalRef existed: the claude case had `itermSessionId` and no `terminal`.
        let json = #"{"claude":{"sessionId":"s1","transcriptPath":"/t","cwd":"/p","itermSessionId":"w0:X"}}"#
        let source = try JSONDecoder().decode(TaskSource.self, from: Data(json.utf8))
        guard case let .claude(sessionId, _, _, terminal) = source else { return XCTFail("not claude") }
        XCTAssertEqual(sessionId, "s1")
        XCTAssertNil(terminal)
    }

    func testTerminalRoundTripsThroughCodable() throws {
        let ref = TerminalRef(program: "Apple_Terminal", itermSessionId: nil, tty: "/dev/ttys004")
        let source = TaskSource.claude(sessionId: "s1", transcriptPath: "/t", cwd: "/p", terminal: ref)
        let data = try JSONEncoder().encode(source)
        XCTAssertEqual(try JSONDecoder().decode(TaskSource.self, from: data), source)
    }

    // MARK: Resolving the focus action

    func testITermSessionResolvesToITermAction() {
        let ref = TerminalRef(program: "iTerm.app", itermSessionId: "w0t3p1:651EB773-1", tty: "/dev/ttys001")
        XCTAssertEqual(TerminalTarget.resolve(ref), .itermSession(uuid: "651EB773-1"))
    }

    func testITermIdWinsEvenWithoutProgram() {
        let ref = TerminalRef(program: nil, itermSessionId: "ABC", tty: nil)
        XCTAssertEqual(TerminalTarget.resolve(ref), .itermSession(uuid: "ABC"))
    }

    func testAppleTerminalResolvesToTabByTTY() {
        let ref = TerminalRef(program: "Apple_Terminal", itermSessionId: nil, tty: "/dev/ttys004")
        XCTAssertEqual(TerminalTarget.resolve(ref), .terminalTab(tty: "/dev/ttys004"))
    }

    func testAppleTerminalWithoutTTYActivatesApp() {
        let ref = TerminalRef(program: "Apple_Terminal", itermSessionId: nil, tty: nil)
        XCTAssertEqual(TerminalTarget.resolve(ref), .activate(bundleId: "com.apple.Terminal"))
    }

    func testKnownProgramActivatesByBundleId() {
        XCTAssertEqual(TerminalTarget.resolve(TerminalRef(program: "ghostty", itermSessionId: nil, tty: "/dev/ttys002")),
                       .activate(bundleId: "com.mitchellh.ghostty"))
        XCTAssertEqual(TerminalTarget.resolve(TerminalRef(program: "vscode", itermSessionId: nil, tty: nil)),
                       .activate(bundleId: "com.microsoft.VSCode"))
    }

    func testUnknownProgramOrNilFallsBack() {
        XCTAssertEqual(TerminalTarget.resolve(TerminalRef(program: "SomethingNew", itermSessionId: nil, tty: "/dev/ttys002")), .none)
        XCTAssertEqual(TerminalTarget.resolve(nil), .none)
    }
}
