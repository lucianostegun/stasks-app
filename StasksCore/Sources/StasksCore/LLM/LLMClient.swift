import Foundation

public enum LLMError: Error, Equatable, Sendable {
    case http(Int, String)
    case transport(String)
    case decoding(String)
    case emptyResponse
    /// A local process (Claude Code CLI) exited non-zero. Carries the exit status and stderr.
    case process(Int32, String)
}

/// One-shot completion used for title generation. Every provider implements this.
public protocol LLMClient: Sendable {
    func complete(system: String, user: String, maxTokens: Int) async throws -> String
}

public typealias AnthropicAPI = LLMClient
public typealias AnthropicError = LLMError
