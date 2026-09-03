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
}
