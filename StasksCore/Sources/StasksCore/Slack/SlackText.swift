import Foundation

/// Turns Slack mrkdwn into plain text for titles: link and mention tokens become their labels, HTML entities are decoded.
public enum SlackText {
    private static let token = try! NSRegularExpression(pattern: #"<([^<>|]+)(?:\|([^<>]*))?>"#)
    private static let mention = try! NSRegularExpression(pattern: #"<@([UW][A-Z0-9]+)(?:\|[^>]*)?>"#)

    /// User ids referenced as `<@U123>` without a label, so the caller can resolve names before calling `plain`.
    public static func mentionedUserIds(_ text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var ids: [String] = []
        for m in mention.matches(in: text, range: range) {
            if let r = Range(m.range(at: 1), in: text) { ids.append(String(text[r])) }
        }
        return ids
    }

    /// `users` maps user id to display name for `<@U123>` tokens. Unknown ids stay as `@U123`.
    public static func plain(_ text: String, users: [String: String] = [:]) -> String {
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for m in token.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let body = ns.substring(with: m.range(at: 1))
            let label: String? = m.range(at: 2).location == NSNotFound ? nil : ns.substring(with: m.range(at: 2))
            out += render(body: body, label: label, users: users)
            cursor = m.range.location + m.range.length
        }
        out += ns.substring(from: cursor)
        return decodeEntities(out)
    }

    private static func render(body: String, label: String?, users: [String: String]) -> String {
        if body.hasPrefix("@") {
            let id = String(body.dropFirst())
            if let label, !label.isEmpty { return "@" + label.trimmingCharacters(in: CharacterSet(charactersIn: "@")) }
            return "@" + (users[id] ?? id)
        }
        if body.hasPrefix("#") {
            if let label, !label.isEmpty { return "#" + label.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            return body
        }
        if body.hasPrefix("!") {
            if let label, !label.isEmpty { return label.hasPrefix("@") ? label : "@" + label }
            let name = body.dropFirst().split(separator: "^").first.map(String.init) ?? ""
            return "@" + name
        }
        // URL or mailto: the label when present, otherwise the target itself.
        if let label, !label.isEmpty { return label }
        return body.hasPrefix("mailto:") ? String(body.dropFirst(7)) : body
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
