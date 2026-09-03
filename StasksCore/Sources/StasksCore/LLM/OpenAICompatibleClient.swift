import Foundation

/// Chat Completions client for OpenAI and anything that speaks its API (Ollama, Groq, OpenRouter, LM Studio).
/// Sends `max_completion_tokens` and no `temperature`, which OpenAI reasoning models reject.
public struct OpenAICompatibleClient: LLMClient {
    public static let defaultBaseURL = "https://api.openai.com/v1"
    public static let defaultModel = "gpt-5-mini"

    private let endpoint: URL
    private let apiKey: String
    private let model: String
    private let session: URLSession

    /// `baseURL` is the API root (e.g. `https://api.openai.com/v1`, `http://localhost:11434/v1`); `/chat/completions` is appended.
    public init(baseURL: String, apiKey: String, model: String, session: URLSession = .shared) {
        var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        self.endpoint = URL(string: root + "/chat/completions") ?? URL(string: Self.defaultBaseURL + "/chat/completions")!
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    public func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = [
            "model": model,
            "max_completion_tokens": maxTokens,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw LLMError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("no http response") }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded: Response
        do { decoded = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw LLMError.decoding(error.localizedDescription) }
        let text = decoded.choices.first?.message.content ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LLMError.emptyResponse }
        return text
    }
}
