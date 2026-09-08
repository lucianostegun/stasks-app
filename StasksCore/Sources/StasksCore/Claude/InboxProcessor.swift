import Foundation

public enum CompletionPhrase {
    // Word-bounded, case-insensitive, accent-insensitive on "concluída".
    private static let regex = try! NSRegularExpression(
        pattern: #"\b(tarefa\s+conclu[ií]da|task\s+done|task\s+complete)\b"#,
        options: [.caseInsensitive])

    public static func matches(_ prompt: String) -> Bool {
        let range = NSRange(prompt.startIndex..., in: prompt)
        return regex.firstMatch(in: prompt, options: [], range: range) != nil
    }
}

/// Applies Claude Code hook events to the store.
///
/// A session becomes a task only when the user sends the first real prompt (not a slash command).
/// Session start never creates anything; it only reopens a Done task on resume.
@MainActor
public struct InboxProcessor {
    private let store: TaskStore
    private let now: @Sendable () -> Date

    public init(store: TaskStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    public func apply(_ events: [InboxEvent]) {
        for e in events { apply(e) }
    }

    public func apply(_ e: InboxEvent) {
        switch e.event {
        case .sessionStart: handleStart(e)
        case .userPromptSubmit: handlePrompt(e)
        case .sessionEnd: handleEnd(e)
        case .stop: setActivity(e, .finished)
        case .notification: setActivity(e, .waitingInput)
        }
    }

    private func handleStart(_ e: InboxEvent) {
        guard e.source == "resume", let existing = store.task(claudeSessionId: e.sessionId), existing.status == .done else { return }
        store.setStatus(id: existing.id, .open)
    }

    private func handlePrompt(_ e: InboxEvent) {
        guard let prompt = e.prompt else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCommand = trimmed.isEmpty || trimmed.hasPrefix("/")

        if let task = store.task(claudeSessionId: e.sessionId) {
            if CompletionPhrase.matches(prompt) {
                store.setStatus(id: task.id, .done)
                return
            }
            if !isCommand { store.setActivity(id: task.id, .working) }
            return
        }

        // No task yet: only a real prompt creates one, titled with that prompt.
        guard !isCommand, !CompletionPhrase.matches(prompt) else { return }
        let cwd = e.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        var task = TaskItem.claude(sessionId: e.sessionId, cwd: cwd, transcriptPath: e.transcriptPath ?? "",
                                   terminal: e.terminal, now: now())
        task.title = TaskItem.truncatedTitle(trimmed)
        task.subtitle = TaskItem.folderName(cwd: cwd)
        task.activity = .working
        store.add(task)
    }

    private func handleEnd(_ e: InboxEvent) {
        guard let task = store.task(claudeSessionId: e.sessionId) else { return }
        store.setStatus(id: task.id, .done)
    }

    private func setActivity(_ e: InboxEvent, _ activity: ClaudeActivity) {
        guard let task = store.task(claudeSessionId: e.sessionId), task.status.isActive else { return }
        store.setActivity(id: task.id, activity)
    }
}
