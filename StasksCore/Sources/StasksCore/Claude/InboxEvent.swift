import Foundation

public struct InboxEvent: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case sessionEnd = "SessionEnd"
    }

    public let event: Kind
    public let sessionId: String
    public let cwd: String?
    public let transcriptPath: String?
    public let source: String?
    public let prompt: String?
    public let reason: String?
    public let itermSessionId: String?
    public let ts: Double?

    public init(event: Kind, sessionId: String, cwd: String?, transcriptPath: String?, source: String?,
                prompt: String?, reason: String?, itermSessionId: String?, ts: Double?) {
        self.event = event; self.sessionId = sessionId; self.cwd = cwd; self.transcriptPath = transcriptPath
        self.source = source; self.prompt = prompt; self.reason = reason; self.itermSessionId = itermSessionId; self.ts = ts
    }
}

public enum InboxParser {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    public static func parse(line: String) -> InboxEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? decoder.decode(InboxEvent.self, from: data)
    }

    public static func parse(data: Data) -> [InboxEvent] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { parse(line: String($0)) }
    }
}
