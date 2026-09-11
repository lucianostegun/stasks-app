import Foundation

/// Finds command line tools from a GUI app, which does not inherit the shell PATH.
public enum ToolLocator {
    /// macOS ships jq in /usr/bin since Sequoia; the rest are the usual Homebrew and user installs.
    public static let defaultDirectories = ["/usr/bin", "/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin"]

    public static func locate(_ name: String, directories: [String] = defaultDirectories,
                              isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        for dir in directories {
            let path = (dir as NSString).expandingTildeInPath + "/" + name
            if isExecutable(path) { return path }
        }
        return nil
    }
}
