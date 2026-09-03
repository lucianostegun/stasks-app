import Foundation

public struct AnthropicClient: LLMClient {
    public static let model = "claude-haiku-4-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    private struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    public func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": maxTokens,
            "temperature": 0.2,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw AnthropicError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.transport("no http response") }
        guard (200..<300).contains(http.statusCode) else {
            throw AnthropicError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded: Response
        do { decoded = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AnthropicError.decoding(error.localizedDescription) }
        let text = decoded.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AnthropicError.emptyResponse }
        return text
    }
}
