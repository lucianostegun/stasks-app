import Foundation
import Observation

@MainActor
@Observable
public final class TaskStore {
    public private(set) var tasks: [TaskItem] = []

    @ObservationIgnored private let persistence: (any TaskPersistence)?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored public var debounceNanos: UInt64 = 200_000_000

    public init(persistence: (any TaskPersistence)?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.persistence = persistence
        self.now = now
        if let loaded = try? persistence?.load() { tasks = loaded }
    }

    // MARK: Mutations

    public func add(_ task: TaskItem) {
        tasks.append(task)
        scheduleSave()
    }

    public func update(id: UUID, _ mutate: (inout TaskItem) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[i])
        scheduleSave()
    }

    public func setStatus(id: UUID, _ status: TaskStatus) {
        let stamp = now()
        update(id: id) { t in
            t.status = status
            t.completedAt = status == .done ? stamp : nil
            if status == .done { t.activity = nil }
        }
    }

    public func setTitle(id: UUID, _ title: String, pinned: Bool) {
        update(id: id) { t in
            t.title = TaskItem.truncatedTitle(title)
            t.isProvisionalTitle = false
            if pinned { t.isPinnedTitle = true }
        }
    }

    public func setSubtitle(id: UUID, _ subtitle: String) {
        update(id: id) { $0.subtitle = subtitle }
    }

    public func setActivity(id: UUID, _ activity: ClaudeActivity?) {
        update(id: id) { $0.activity = activity }
    }

    public func remove(id: UUID) {
        tasks.removeAll { $0.id == id }
        scheduleSave()
    }

    public func purgeCompleted(olderThanDays days: Int) {
        let cutoff = now().addingTimeInterval(-Double(days) * 86_400)
        let before = tasks.count
        tasks.removeAll { $0.status == .done && ($0.completedAt ?? $0.createdAt) < cutoff }
        if tasks.count != before { scheduleSave() }
    }

    // MARK: Queries

    public func task(id: UUID) -> TaskItem? { tasks.first { $0.id == id } }

    public func task(claudeSessionId: String) -> TaskItem? {
        tasks.first { $0.source.claudeSessionId == claudeSessionId }
    }

    public func task(slackChannelId: String, ts: String) -> TaskItem? {
        tasks.first { $0.source.slackKey == "\(slackChannelId):\(ts)" }
    }

    public func activeTasks(order: StackOrder) -> [TaskItem] {
        let active = tasks.filter { $0.status.isActive }
        switch order {
        case .lifo: return active.sorted { $0.createdAt > $1.createdAt }
        case .fifo: return active.sorted { $0.createdAt < $1.createdAt }
        }
    }

    public var activeCount: Int { tasks.filter { $0.status.isActive }.count }

    public func completedTasks(withinHours hours: Double) -> [TaskItem] {
        let cutoff = now().addingTimeInterval(-hours * 3600)
        return tasks
            .filter { $0.status == .done && ($0.completedAt ?? $0.createdAt) >= cutoff }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = tasks
        let persistence = self.persistence
        let delay = debounceNanos
        saveTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            do { try persistence?.save(snapshot) }
            catch { Log.ui.error("task save failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    public func flush() {
        saveTask?.cancel()
        do { try persistence?.save(tasks) }
        catch { Log.ui.error("task save failed: \(error.localizedDescription, privacy: .public)") }
    }
}
