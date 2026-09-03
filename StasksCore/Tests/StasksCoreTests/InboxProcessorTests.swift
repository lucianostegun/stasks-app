import XCTest
@testable import StasksCore

@MainActor
final class InboxProcessorTests: XCTestCase {
    var store: TaskStore!
    var processor: InboxProcessor!
    let clock = Date(timeIntervalSince1970: 1_000)

    override func setUp() {
        store = TaskStore(persistence: nil, now: { [clock] in clock })
        processor = InboxProcessor(store: store, now: { [clock] in clock })
    }

    func ev(_ kind: InboxEvent.Kind, session: String = "S1", cwd: String? = "/Users/x/soci-app", transcript: String? = "/t.jsonl",
            source: String? = "startup", prompt: String? = nil, iterm: String? = "w0:ID") -> InboxEvent {
        InboxEvent(event: kind, sessionId: session, cwd: cwd, transcriptPath: transcript, source: source, prompt: prompt, reason: nil, itermSessionId: iterm, ts: nil)
    }

    func testSessionStartCreatesOpenTaskWithFolderTitle() {
        processor.apply(ev(.sessionStart))
        let t = store.task(claudeSessionId: "S1")
        XCTAssertEqual(t?.title, "soci-app")
        XCTAssertEqual(t?.status, .open)
        if case let .claude(_, transcript, cwd, iterm)? = t?.source {
            XCTAssertEqual(transcript, "/t.jsonl"); XCTAssertEqual(cwd, "/Users/x/soci-app"); XCTAssertEqual(iterm, "w0:ID")
        } else { XCTFail("wrong source") }
    }

    func testDuplicateSessionStartDoesNotDuplicate() {
        processor.apply(ev(.sessionStart)); processor.apply(ev(.sessionStart))
        XCTAssertEqual(store.tasks.count, 1)
    }

    func testCompactIsIgnored() {
        processor.apply(ev(.sessionStart, source: "compact"))
        XCTAssertEqual(store.tasks.count, 0)
    }

    func testResumeReopensDoneTask() {
        processor.apply(ev(.sessionStart))
        processor.apply(ev(.sessionEnd))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.status, .done)
        processor.apply(ev(.sessionStart, source: "resume"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.status, .open)
        XCTAssertEqual(store.tasks.count, 1)
    }

    func testResumeWithoutTaskCreatesOne() {
        processor.apply(ev(.sessionStart, source: "resume"))
        XCTAssertEqual(store.tasks.count, 1)
    }

    func testFirstPromptBecomesTitleOnlyOnce() {
        processor.apply(ev(.sessionStart))
        processor.apply(ev(.userPromptSubmit, prompt: "Fix the login bug\nmore details"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.title, "Fix the login bug")
        processor.apply(ev(.userPromptSubmit, prompt: "Second prompt"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.title, "Fix the login bug")
    }

    func testSlashCommandPromptDoesNotBecomeTitle() {
        processor.apply(ev(.sessionStart))
        processor.apply(ev(.userPromptSubmit, prompt: "/clear"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.title, "soci-app")
        processor.apply(ev(.userPromptSubmit, prompt: "Real prompt"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.title, "Real prompt")
    }

    func testPinnedTitleIsNotOverwrittenByPrompt() {
        processor.apply(ev(.sessionStart))
        let id = store.task(claudeSessionId: "S1")!.id
        store.setTitle(id: id, "Renamed", pinned: true)
        processor.apply(ev(.userPromptSubmit, prompt: "whatever"))
        XCTAssertEqual(store.task(id: id)?.title, "Renamed")
    }

    func testCompletionPhrasesMarkDone() {
        for phrase in ["Tarefa concluída", "ok, task done!", "TASK COMPLETE", "tarefa concluida"] {
            store = TaskStore(persistence: nil); processor = InboxProcessor(store: store)
            processor.apply(ev(.sessionStart))
            processor.apply(ev(.userPromptSubmit, prompt: phrase))
            XCTAssertEqual(store.task(claudeSessionId: "S1")?.status, .done, phrase)
        }
    }

    func testPhraseInsideSentenceStillCompletes() {
        processor.apply(ev(.sessionStart))
        processor.apply(ev(.userPromptSubmit, prompt: "is the task done yet? no, keep going with tasks"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.status, .done)
    }

    func testNonCompletionPhraseStaysOpen() {
        processor.apply(ev(.sessionStart))
        processor.apply(ev(.userPromptSubmit, prompt: "tasks are done"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.status, .open)
    }

    func testPromptForUnknownSessionCreatesTaskLazily() {
        processor.apply(ev(.userPromptSubmit, prompt: "hello"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.title, "hello")
    }

    func testSessionEndForUnknownSessionIsNoop() {
        processor.apply(ev(.sessionEnd))
        XCTAssertEqual(store.tasks.count, 0)
    }
}
