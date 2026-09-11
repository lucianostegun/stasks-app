import XCTest
@testable import StasksCore

final class HookScriptTests: XCTestCase {
    var dir: URL!
    var bundled: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        bundled = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sh")
        try "#!/bin/bash\necho v1\n".write(to: bundled, atomically: true, encoding: .utf8)
    }

    func perms(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    func testCopiesWhenMissingAndMakesExecutable() throws {
        let dest = try HookScript.sync(bundled: bundled, directory: dir)
        XCTAssertEqual(dest.lastPathComponent, "stasks-hook.sh")
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "#!/bin/bash\necho v1\n")
        XCTAssertEqual(try perms(dest) & 0o777, 0o755)
    }

    func testOverwritesWhenContentDiffers() throws {
        let dest = try HookScript.sync(bundled: bundled, directory: dir)
        try "#!/bin/bash\necho v2\n".write(to: bundled, atomically: true, encoding: .utf8)
        _ = try HookScript.sync(bundled: bundled, directory: dir)
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "#!/bin/bash\necho v2\n")
    }

    func testLeavesIdenticalCopyAloneButFixesPermissions() throws {
        let dest = try HookScript.sync(bundled: bundled, directory: dir)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest.path)
        let before = try FileManager.default.attributesOfItem(atPath: dest.path)[.modificationDate] as? Date
        _ = try HookScript.sync(bundled: bundled, directory: dir)
        let after = try FileManager.default.attributesOfItem(atPath: dest.path)[.modificationDate] as? Date
        XCTAssertEqual(before, after)
        XCTAssertEqual(try perms(dest) & 0o777, 0o755)
    }
}
