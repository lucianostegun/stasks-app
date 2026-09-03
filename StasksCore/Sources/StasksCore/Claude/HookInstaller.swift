import Foundation

public enum HookStatus: Equatable, Sendable {
    case installed
    case outdated(currentCommand: String)
    case missing
}

public struct HookInstaller {
    public static let events = ["SessionStart", "UserPromptSubmit", "SessionEnd"]
    private static let marker = "stasks-hook.sh"

    public let settingsURL: URL
    public let scriptPath: String

    public init(settingsURL: URL, scriptPath: String) {
        self.settingsURL = settingsURL
        self.scriptPath = scriptPath
    }

    public var command: String { "bash \"\(scriptPath)\"" }

    public func status() throws -> HookStatus {
        let root = try load()
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        var found: [String] = []
        for event in Self.events {
            let groups = hooks[event] as? [[String: Any]] ?? []
            let ours = groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
                .compactMap { $0["command"] as? String }
                .first { $0.contains(Self.marker) }
            guard let ours else { return .missing }
            found.append(ours)
        }
        if let stale = found.first(where: { $0 != command }) { return .outdated(currentCommand: stale) }
        return .installed
    }

    @discardableResult
    public func install() throws -> URL {
        var root = try load()
        let backup = try writeBackup()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            var replaced = false
            groups = groups.map { group in
                var g = group
                var inner = g["hooks"] as? [[String: Any]] ?? []
                inner = inner.map { h in
                    guard let c = h["command"] as? String, c.contains(Self.marker) else { return h }
                    replaced = true
                    var hh = h; hh["command"] = command; return hh
                }
                g["hooks"] = inner
                return g
            }
            if !replaced {
                groups.append(["hooks": [["type": "command", "command": command]]])
            }
            hooks[event] = groups
        }
        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
        return backup
    }

    private func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Stasks.HookInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "settings.json is not a JSON object"])
        }
        return obj
    }

    private func writeBackup() throws -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.stasks-backup-\(stamp)")
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        } else {
            try Data("{}".utf8).write(to: backup)
        }
        return backup
    }
}
