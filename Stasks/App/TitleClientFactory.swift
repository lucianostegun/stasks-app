import Foundation
import StasksCore

/// Builds the title-generation client for the provider chosen in Settings. Read at call time so changes apply without restart.
enum TitleClientFactory {
    static func make(_ prefs: Preferences) -> (any LLMClient)? {
        switch prefs.titleProvider {
        case .anthropic:
            guard let key = KeychainStore.get(KeychainStore.anthropicKey), !key.isEmpty else { return nil }
            return AnthropicClient(apiKey: key)
        case .openAI:
            // Local servers (Ollama, LM Studio) take no key, so an empty key is allowed here.
            let key = KeychainStore.get(KeychainStore.openAIKey) ?? ""
            guard !prefs.openAIBaseURL.isEmpty, !prefs.openAIModel.isEmpty else { return nil }
            return OpenAICompatibleClient(baseURL: prefs.openAIBaseURL, apiKey: key, model: prefs.openAIModel)
        case .claudeCode:
            guard let exe = resolvedClaudePath(prefs) else { return nil }
            return ClaudeCodeClient(executable: exe, model: prefs.claudeCodeModel.isEmpty ? ClaudeCodeClient.defaultModel : prefs.claudeCodeModel)
        }
    }

    static func isConfigured(_ prefs: Preferences) -> Bool { make(prefs) != nil }

    /// User-set path when it points at an executable, otherwise the first known install location.
    static func resolvedClaudePath(_ prefs: Preferences) -> String? {
        let custom = (prefs.claudeCodePath as NSString).expandingTildeInPath
        if !prefs.claudeCodePath.isEmpty, FileManager.default.isExecutableFile(atPath: custom) { return custom }
        return ClaudeCodeClient.locate()
    }
}
