import Foundation

public struct TitleGenerator: TitleGenerating {
    private let client: any LLMClient

    public init(client: any LLMClient) { self.client = client }

    public func title(channel: String, author: String, text: String, thread: [(author: String, text: String)]) async -> String? {
        let prompt = TitlePromptBuilder.user(channel: channel, author: author, text: text, thread: thread)
        do {
            let raw = try await client.complete(system: TitlePromptBuilder.system, user: prompt, maxTokens: 60)
            let cleaned = TitlePromptBuilder.clean(raw)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            Log.llm.error("title generation failed: \(Self.reason(error), privacy: .public)")
            return nil
        }
    }

    /// Never logs response bodies: only the failure kind (and the HTTP status when there is one).
    private static func reason(_ error: any Error) -> String {
        switch error as? LLMError {
        case let .http(status, _): return "http \(status)"
        case let .process(status, _): return "process exit \(status)"
        case .transport: return "transport"
        case .decoding: return "decoding"
        case .emptyResponse: return "empty response"
        case nil: return "unknown"
        }
    }
}
