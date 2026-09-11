import Foundation

/// Keeps a copy of the bundled hook script at a path that does not move with the app bundle.
/// `~/.claude/settings.json` points at that copy, so relocating or reinstalling Stasks.app does not break the hooks.
public enum HookScript {
    public static let fileName = "stasks-hook.sh"

    /// Copies `bundled` into `directory` when the copy is missing or differs, and makes it executable.
    /// The write is atomic: a hook already running keeps reading the old inode.
    @discardableResult
    public static func sync(bundled: URL, directory: URL) throws -> URL {
        let fm = FileManager.default
        let dest = directory.appendingPathComponent(fileName)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try Data(contentsOf: bundled)
        if (try? Data(contentsOf: dest)) != source {
            try source.write(to: dest, options: .atomic)
        }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return dest
    }
}
