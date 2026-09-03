import Foundation

public enum TranscriptParser {
    private struct Line: Decodable {
        let type: String
        let customTitle: String?
    }

    public static func customTitle(line: String) -> String? {
        // Cheap pre-filter: avoid decoding every transcript line.
        guard line.contains("\"custom-title\""), let data = line.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Line.self, from: data),
              decoded.type == "custom-title" else { return nil }
        return decoded.customTitle
    }

    public static func latestCustomTitle(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var latest: String?
        for line in text.split(separator: "\n") {
            if let t = customTitle(line: String(line)) { latest = t }
        }
        return latest
    }

    // MARK: Assistant messages

    private struct MessageLine: Decodable {
        struct Message: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let role: String?
            let content: Content?
            enum Content: Decodable {
                case text(String)
                case blocks([Block])
                init(from decoder: Decoder) throws {
                    let c = try decoder.singleValueContainer()
                    if let s = try? c.decode(String.self) { self = .text(s); return }
                    self = .blocks(try c.decode([Block].self))
                }
            }
        }
        let type: String
        let isSidechain: Bool?
        let message: Message?
    }

    /// Text of one main-thread assistant line, or nil for user lines, tool-only turns, sidechains and non-message lines.
    public static func assistantText(line: String) -> String? {
        guard line.contains("\"assistant\""), line.contains("\"text\""), let data = line.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(MessageLine.self, from: data),
              decoded.type == "assistant", decoded.isSidechain != true,
              let content = decoded.message?.content else { return nil }
        let text: String
        switch content {
        case .text(let s): text = s
        case .blocks(let blocks): text = blocks.filter { $0.type == "text" }.compactMap(\.text).joined(separator: "\n")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The most recent assistant text in the given transcript bytes.
    public static func lastAssistantText(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var latest: String?
        for line in text.split(separator: "\n") {
            if let t = assistantText(line: String(line)) { latest = t }
        }
        return latest
    }
}
