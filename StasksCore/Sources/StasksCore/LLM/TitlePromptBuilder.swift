import Foundation

public enum TitlePromptBuilder {
    public static let maxThread = 15

    public static let system = """
    Você recebe uma mensagem do Slack e, quando existe, o contexto da thread. \
    Gere um título de tarefa acionável para quem vai responder ou agir sobre a mensagem. \
    Responda só com o título, no idioma da mensagem, máximo 60 caracteres, sem aspas, sem ponto final, sem prefixos como "Título:".
    """

    public static func user(channel: String, author: String, text: String, thread: [(author: String, text: String)]) -> String {
        var lines = ["Canal: #\(channel)", "Autor: \(author)", "", "Mensagem:", text]
        let tail = thread.suffix(maxThread)
        if !tail.isEmpty {
            lines += ["", "Thread (mais antigas primeiro):"]
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
