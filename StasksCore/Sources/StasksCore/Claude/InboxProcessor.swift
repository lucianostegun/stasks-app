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
        }
    }

    private func handleStart(_ e: InboxEvent) {
        if e.source == "compact" { return }
        if let existing = store.task(claudeSessionId: e.sessionId) {
            if existing.status == .done { store.setStatus(id: existing.id, .open) }
            return
        }
        createTask(from: e)
    }

    @discardableResult
    private func createTask(from e: InboxEvent) -> TaskItem {
        let task = TaskItem.claude(sessionId: e.sessionId,
                                   cwd: e.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path,
                                   transcriptPath: e.transcriptPath ?? "",
                                   itermSessionId: e.itermSessionId,
                                   now: now())
        store.add(task)
        return task
    }

    private func handlePrompt(_ e: InboxEvent) {
        guard let prompt = e.prompt else { return }
        let task = store.task(claudeSessionId: e.sessionId) ?? createTask(from: e)

        if CompletionPhrase.matches(prompt) {
            store.setStatus(id: task.id, .done)
            return
        }
        guard !task.isPinnedTitle else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { return }
        let folderTitle = TaskItem.folderName(cwd: claudeCwd(task) ?? "")
        guard task.title == folderTitle else { return }
        store.setTitle(id: task.id, trimmed, pinned: false)
    }

    private func handleEnd(_ e: InboxEvent) {
        guard let task = store.task(claudeSessionId: e.sessionId) else { return }
        store.setStatus(id: task.id, .done)
    }

    private func claudeCwd(_ task: TaskItem) -> String? {
        if case let .claude(_, _, cwd, _) = task.source { return cwd }
        return nil
    }
}
