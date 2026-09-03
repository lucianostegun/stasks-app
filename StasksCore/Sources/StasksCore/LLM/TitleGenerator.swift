import Foundation

public struct TitleGenerator: TitleGenerating {
    private let client: any AnthropicAPI

    public init(client: any AnthropicAPI) { self.client = client }

    public func title(channel: String, author: String, text: String, thread: [(author: String, text: String)]) async -> String? {
        let prompt = TitlePromptBuilder.user(channel: channel, author: author, text: text, thread: thread)
        do {
            let raw = try await client.complete(system: TitlePromptBuilder.system, user: prompt, maxTokens: 60)
            let cleaned = TitlePromptBuilder.clean(raw)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            Log.llm.error("title generation failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
