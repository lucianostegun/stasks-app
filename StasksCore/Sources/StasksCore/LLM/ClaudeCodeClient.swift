import Foundation

/// Runs `claude -p` so titles use the user's Claude Code login instead of an API key.
/// `--setting-sources ""` is essential: without it the user's hooks fire and Stasks would create a task for every title.
public struct ClaudeCodeClient: LLMClient {
    public static let defaultModel = "haiku"
    public static let searchPaths = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    public let executable: String
    public let model: String
    public let timeout: TimeInterval
    /// Where `claude` runs. Must be an empty, dedicated folder: Claude Code treats its cwd as the project root and
    /// scans it, and a GUI app's cwd is `/`, which would touch Desktop, Downloads and /Volumes and trigger TCC prompts.
    public let workingDirectory: URL

    public static let defaultWorkingDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Stasks/claude-workdir")

    public init(executable: String, model: String = ClaudeCodeClient.defaultModel, timeout: TimeInterval = 60,
                workingDirectory: URL = ClaudeCodeClient.defaultWorkingDirectory) {
        self.executable = executable
        self.model = model
        self.timeout = timeout
        self.workingDirectory = workingDirectory
    }

    /// First executable found among `searchPaths`, or nil when Claude Code is not installed.
    public static func locate() -> String? {
        for p in searchPaths {
            let path = (p as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    public static func arguments(system: String, user: String, model: String) -> [String] {
        ["-p", "--model", model,
         "--setting-sources", "",
         "--tools", "",
         "--strict-mcp-config",
         "--disable-slash-commands",
         "--no-session-persistence",
         "--output-format", "text",
         "--system-prompt", system,
         user]
    }

    /// `maxTokens` is ignored: the CLI has no such flag and the system prompt already bounds the title length.
    public func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        let args = Self.arguments(system: system, user: user, model: model)
        let exe = executable, timeout = timeout, cwd = workingDirectory
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                try? FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                p.currentDirectoryURL = cwd
                p.standardInput = FileHandle.nullDevice
                var env = ProcessInfo.processInfo.environment
                let path = env["PATH"] ?? ""
                env["PATH"] = ["/usr/local/bin", "/opt/homebrew/bin", NSHomeDirectory() + "/.local/bin", path].joined(separator: ":")
                p.environment = env
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch { cont.resume(throwing: LLMError.transport(error.localizedDescription)); return }

                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()

                guard p.terminationStatus == 0 else {
                    let stderr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    cont.resume(throwing: LLMError.process(p.terminationStatus, stderr))
                    return
                }
                let text = String(data: outData, encoding: .utf8) ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { cont.resume(throwing: LLMError.emptyResponse); return }
                cont.resume(returning: text)
            }
        }
    }
}
