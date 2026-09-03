import XCTest
@testable import StasksCore

final class ClaudeCodeClientTests: XCTestCase {
    /// Writes a fake `claude` that records its arguments and prints a canned answer (or fails).
    func fakeExecutable(_ body: String) throws -> (exe: String, argsFile: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stasks-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exe = dir.appendingPathComponent("claude").path
        let argsFile = dir.appendingPathComponent("args.txt").path
        let script = "#!/bin/bash\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done > \"\(argsFile)\"\n\(body)\n"
        try script.write(toFile: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe)
        return (exe, argsFile)
    }

    func testPassesHeadlessFlagsAndReadsStdout() async throws {
        let (exe, argsFile) = try fakeExecutable("echo 'Review PR 42'")
        let text = try await ClaudeCodeClient(executable: exe, model: "haiku").complete(system: "SYS", user: "USR", maxTokens: 60)
        XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "Review PR 42")
        let args = try String(contentsOfFile: argsFile, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(args.dropLast(), ClaudeCodeClient.arguments(system: "SYS", user: "USR", model: "haiku")[...])
        // Hooks must stay off, otherwise every title would create a Stasks task.
        XCTAssertTrue(args.contains("--setting-sources"))
        XCTAssertEqual(args[args.firstIndex(of: "--setting-sources")! + 1], "")
        XCTAssertTrue(args.contains("--no-session-persistence"))
        XCTAssertEqual(args.last, "")   // trailing newline from the recorder
    }

    func testRunsInsideDedicatedEmptyWorkingDirectory() async throws {
        let (exe, _) = try fakeExecutable("pwd")
        let cwd = FileManager.default.temporaryDirectory.appendingPathComponent("stasks-cwd-\(UUID().uuidString)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cwd.path))
        let text = try await ClaudeCodeClient(executable: exe, workingDirectory: cwd).complete(system: "s", user: "u", maxTokens: 10)
        XCTAssertEqual(URL(fileURLWithPath: text.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath().path,
                       cwd.resolvingSymlinksInPath().path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cwd.path))   // created on demand
    }

    func testNonZeroExitBecomesProcessError() async throws {
        let (exe, _) = try fakeExecutable("echo 'not logged in' >&2; exit 3")
        do { _ = try await ClaudeCodeClient(executable: exe).complete(system: "s", user: "u", maxTokens: 10); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? LLMError, .process(3, "not logged in")) }
    }

    func testEmptyOutputIsEmptyResponse() async throws {
        let (exe, _) = try fakeExecutable("echo '   '")
        do { _ = try await ClaudeCodeClient(executable: exe).complete(system: "s", user: "u", maxTokens: 10); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? LLMError, .emptyResponse) }
    }

    func testMissingExecutableIsTransportError() async {
        do { _ = try await ClaudeCodeClient(executable: "/nonexistent/claude").complete(system: "s", user: "u", maxTokens: 10); XCTFail("expected error") }
        catch { if case .transport = error as? LLMError {} else { XCTFail("unexpected \(error)") } }
    }
}
