import XCTest
@testable import StasksCore

@MainActor
final class TaskStoreTests: XCTestCase {
    final class MemoryPersistence: TaskPersistence, @unchecked Sendable {
        var saved: [[TaskItem]] = []
        var initial: [TaskItem] = []
        func load() throws -> [TaskItem] { initial }
        func save(_ tasks: [TaskItem]) throws { saved.append(tasks) }
    }

    nonisolated(unsafe) var clock = Date(timeIntervalSince1970: 100_000)
    func makeStore(_ p: MemoryPersistence? = nil) -> TaskStore {
        let store = TaskStore(persistence: p, now: { [self] in self.clock })
        store.debounceNanos = 1_000_000
        return store
    }
    func manual(_ title: String, at offset: TimeInterval = 0) -> TaskItem {
        TaskItem.manual(title: title, now: clock.addingTimeInterval(offset))
    }

    func testAddAndSetStatusSetsCompletedAt() {
        let s = makeStore()
        let t = manual("a")
        s.add(t)
        s.setStatus(id: t.id, .done)
        XCTAssertEqual(s.task(id: t.id)?.status, .done)
        XCTAssertEqual(s.task(id: t.id)?.completedAt, clock)
        s.setStatus(id: t.id, .open)
        XCTAssertNil(s.task(id: t.id)?.completedAt)
    }

    func testLifoAndFifoOrdering() {
        let s = makeStore()
        let a = manual("a", at: 0), b = manual("b", at: 10), c = manual("c", at: 20)
        s.add(a); s.add(b); s.add(c)
        XCTAssertEqual(s.activeTasks(order: .lifo).map(\.title), ["c", "b", "a"])
        XCTAssertEqual(s.activeTasks(order: .fifo).map(\.title), ["a", "b", "c"])
    }

    func testActiveExcludesDoneAndCountsBothActiveStates() {
        let s = makeStore()
        let a = manual("a"), b = manual("b"), c = manual("c")
        s.add(a); s.add(b); s.add(c)
        s.setStatus(id: a.id, .done)
        s.setStatus(id: b.id, .inProgress)
        XCTAssertEqual(s.activeTasks(order: .fifo).map(\.title), ["b", "c"])
        XCTAssertEqual(s.activeCount, 2)
    }

    func testCompletedWithinHours() {
        let s = makeStore()
        let old = manual("old"), fresh = manual("fresh")
        s.add(old); s.add(fresh)
        s.setStatus(id: old.id, .done)
        clock = clock.addingTimeInterval(9 * 3600)
        s.setStatus(id: fresh.id, .done)
        XCTAssertEqual(s.completedTasks(withinHours: 8).map(\.title), ["fresh"])
    }

    func testPurgeRemovesOldDoneOnly() {
        let s = makeStore()
        let old = manual("old"), keep = manual("keep")
        s.add(old); s.add(keep)
        s.setStatus(id: old.id, .done)
        clock = clock.addingTimeInterval(8 * 86_400)
        s.purgeCompleted(olderThanDays: 7)
        XCTAssertEqual(s.tasks.map(\.title), ["keep"])
    }

    func testLookupsByClaudeSessionAndSlackKey() {
        let s = makeStore()
        s.add(TaskItem.claude(sessionId: "s1", cwd: "/a", transcriptPath: "/t", terminal: nil, now: clock))
        s.add(TaskItem.slack(teamId: "T", channelId: "C1", channelName: "c", ts: "9.9", permalink: "", text: "x", author: "a", isDM: false, now: clock))
        XCTAssertNotNil(s.task(claudeSessionId: "s1"))
        XCTAssertNil(s.task(claudeSessionId: "nope"))
        XCTAssertNotNil(s.task(slackChannelId: "C1", ts: "9.9"))
    }

    func testAttentionCallbackFiresOnlyWhenEnteringWaitingInput() {
        let s = makeStore()
        let t = manual("a")
        s.add(t)
        var fired: [UUID] = []
        s.onAttentionRequested = { fired.append($0.id) }
        s.setActivity(id: t.id, .working)
        XCTAssertEqual(fired, [])
        s.setActivity(id: t.id, .waitingInput)
        XCTAssertEqual(fired, [t.id])
        s.setActivity(id: t.id, .waitingInput)   // repeated notification while still waiting: silent
        XCTAssertEqual(fired, [t.id])
        s.setActivity(id: t.id, .finished)
        s.setActivity(id: t.id, .waitingInput)
        XCTAssertEqual(fired, [t.id, t.id])
    }

    func testAttentionCallbackSkipsDoneTasks() {
        let s = makeStore()
        let t = manual("a")
        s.add(t)
        s.setStatus(id: t.id, .done)
        var count = 0
        s.onAttentionRequested = { _ in count += 1 }
        s.setActivity(id: t.id, .waitingInput)
        XCTAssertEqual(count, 0)
    }

    func testSetTitlePinned() {
        let s = makeStore()
        let t = manual("a"); s.add(t)
        s.setTitle(id: t.id, "Renamed", pinned: true)
        XCTAssertEqual(s.task(id: t.id)?.title, "Renamed")
        XCTAssertTrue(s.task(id: t.id)!.isPinnedTitle)
        XCTAssertFalse(s.task(id: t.id)!.isProvisionalTitle)
    }

    func testLoadsFromPersistenceAndSavesDebounced() async throws {
        let p = MemoryPersistence()
        p.initial = [manual("seed")]
        let s = makeStore(p)
        XCTAssertEqual(s.tasks.map(\.title), ["seed"])
        s.add(manual("x")); s.add(manual("y"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(p.saved.count, 1)
        XCTAssertEqual(p.saved.last?.count, 3)
    }

    func testJSONFilePersistenceRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("tasks.json")
        let p = JSONFilePersistence(url: url)
        XCTAssertEqual(try p.load(), [])
        let items = [manual("a")]
        try p.save(items)
        XCTAssertEqual(try p.load(), items)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tasks.json.tmp").path))
    }
}
