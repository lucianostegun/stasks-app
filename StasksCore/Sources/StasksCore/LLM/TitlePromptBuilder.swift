import Foundation

public enum TitlePromptBuilder {
    public static let maxThread = 15

    public static let system = """
    You receive a Slack message and, when present, its thread context. \
    Write an actionable task title for the person who will reply to or act on the message. \
    Answer with the title only, in the language of the message, at most 60 characters, no quotes, no trailing period, no prefixes such as "Title:".
    """

    public static func user(channel: String, author: String, text: String, thread: [(author: String, text: String)]) -> String {
        var lines = ["Channel: #\(channel)", "Author: \(author)", "", "Message:", text]
        let tail = thread.suffix(maxThread)
        if !tail.isEmpty {
            lines += ["", "Thread (oldest first):"]
            lines += tail.map { "\($0.author): \($0.text)" }
        }
        return lines.joined(separator: "\n")
    }

    public static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.split(separator: "\n").first.map(String.init) ?? s
        for prefix in ["Título:", "Titulo:", "Title:"] where s.lowercased().hasPrefix(prefix.lowercased()) {
            s = String(s.dropFirst(prefix.count))
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019} \n"))
        while s.hasSuffix(".") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.count > TaskItem.maxTitleLength { s = String(s.prefix(TaskItem.maxTitleLength - 1)) + "…" }
        return s
    }
}
