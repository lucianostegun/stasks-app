import XCTest
@testable import StasksCore

final class HookInstallerTests: XCTestCase {
    var url: URL!
    let script = "/Applications/Stasks.app/Contents/Resources/stasks-hook.sh"

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("settings.json")
    }

    func write(_ json: String) throws { try json.write(to: url, atomically: true, encoding: .utf8) }
    func read() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }
    func commands(_ obj: [String: Any], _ event: String) -> [String] {
        let groups = (obj["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
    }

    func testMissingWhenNoHooks() throws {
        try write(#"{"permissions":{"allow":["Read"]}}"#)
        XCTAssertEqual(try HookInstaller(settingsURL: url, scriptPath: script).status(), .missing)
    }

    func testInstallPreservesExistingHooksAndOtherKeys() throws {
        try write(#"{"model":"opus","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node other.js"}]}],"Notification":[{"hooks":[{"type":"command","command":"say hi"}]}]}}"#)
        let inst = HookInstaller(settingsURL: url, scriptPath: script)
        let backup = try inst.install()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let obj = try read()
        XCTAssertEqual(obj["model"] as? String, "opus")
        XCTAssertEqual(commands(obj, "SessionStart"), ["node other.js", inst.command])
        XCTAssertEqual(commands(obj, "UserPromptSubmit"), [inst.command])
        XCTAssertEqual(commands(obj, "SessionEnd"), [inst.command])
        XCTAssertEqual(commands(obj, "Notification"), ["say hi"])
        XCTAssertEqual(try inst.status(), .installed)
    }

    func testInstallIsIdempotent() throws {
        try write("{}")
        let inst = HookInstaller(settingsURL: url, scriptPath: script)
        _ = try inst.install(); _ = try inst.install()
        XCTAssertEqual(commands(try read(), "SessionEnd").count, 1)
    }

    func testOutdatedWhenPathDiffersAndInstallReplaces() throws {
        try write(#"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash \"/old/stasks-hook.sh\""}]}],"UserPromptSubmit":[{"hooks":[{"type":"command","command":"bash \"/old/stasks-hook.sh\""}]}],"SessionEnd":[{"hooks":[{"type":"command","command":"bash \"/old/stasks-hook.sh\""}]}]}}"#)
        let inst = HookInstaller(settingsURL: url, scriptPath: script)
        XCTAssertEqual(try inst.status(), .outdated(currentCommand: "bash \"/old/stasks-hook.sh\""))
        _ = try inst.install()
        XCTAssertEqual(commands(try read(), "SessionStart"), [inst.command])
        XCTAssertEqual(try inst.status(), .installed)
    }

    func testPartialInstallIsMissing() throws {
        try write(#"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash \"\#(script)\""}]}]}}"#)
        XCTAssertEqual(try HookInstaller(settingsURL: url, scriptPath: script).status(), .missing)
    }

    func testInstallCreatesFileWhenAbsent() throws {
        let inst = HookInstaller(settingsURL: url, scriptPath: script)
        _ = try inst.install()
        XCTAssertEqual(try inst.status(), .installed)
    }

    func testInstallCollapsesDuplicateStasksEntries() throws {
        try write(#"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node other.js"}],"matcher":"foo"},{"hooks":[{"type":"command","command":"bash \"/old/stasks-hook.sh\""}]},{"hooks":[{"type":"command","command":"bash \"/older/stasks-hook.sh\""}]}]}}"#)
        let inst = HookInstaller(settingsURL: url, scriptPath: script)
        _ = try inst.install()
        let obj = try read()

        XCTAssertEqual(commands(obj, "SessionStart"), ["node other.js", inst.command])

        let groups = (obj["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]] ?? []
        let nonStasksGroup = groups.first { group in
            let hooks = group["hooks"] as? [[String: Any]] ?? []
            return hooks.contains { ($0["command"] as? String) == "node other.js" }
        }
        XCTAssertEqual(nonStasksGroup?["matcher"] as? String, "foo")

        XCTAssertEqual(try inst.status(), .installed)
    }
}
