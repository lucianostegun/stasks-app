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
            source: String? = "startup", prompt: String? = nil, iterm: String? = "w0:ID", message: String? = nil) -> InboxEvent {
        InboxEvent(event: kind, sessionId: session, cwd: cwd, transcriptPath: transcript, source: source, prompt: prompt,
                   reason: nil, itermSessionId: iterm, ts: nil, message: message)
    }

    // MARK: Session start never creates a task

    func testSessionStartCreatesNothing() {
        processor.apply(ev(.sessionStart))
        processor.apply(ev(.sessionStart, source: "clear"))
        processor.apply(ev(.sessionStart, source: "compact"))
        processor.apply(ev(.sessionStart, source: "resume"))
        XCTAssertEqual(store.tasks.count, 0)
    }

    func testResumeReopensDoneTask() {
        processor.apply(ev(.userPromptSubmit, prompt: "Fix the login bug"))
        processor.apply(ev(.sessionEnd))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.status, .done)
        processor.apply(ev(.sessionStart, source: "resume"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.status, .open)
        XCTAssertEqual(store.tasks.count, 1)
    }

    // MARK: First real prompt creates the task

    func testFirstPromptCreatesTaskTitledWithPrompt() {
        processor.apply(ev(.userPromptSubmit, prompt: "Fix the login bug\nmore details"))
        let t = store.task(claudeSessionId: "S1")
        XCTAssertEqual(t?.title, "Fix the login bug")
        XCTAssertEqual(t?.subtitle, "soci-app")
        XCTAssertEqual(t?.status, .open)
        XCTAssertEqual(t?.activity, .working)
        if case let .claude(_, transcript, cwd, iterm)? = t?.source {
            XCTAssertEqual(transcript, "/t.jsonl"); XCTAssertEqual(cwd, "/Users/x/soci-app"); XCTAssertEqual(iterm, "w0:ID")
        } else { XCTFail("wrong source") }
    }

    func testSecondPromptDoesNotRetitleButMarksWorking() {
        processor.apply(ev(.userPromptSubmit, prompt: "First"))
        let id = store.task(claudeSessionId: "S1")!.id
        store.setActivity(id: id, .finished)
        processor.apply(ev(.userPromptSubmit, prompt: "Second"))
        XCTAssertEqual(store.task(id: id)?.title, "First")
        XCTAssertEqual(store.task(id: id)?.activity, .working)
        XCTAssertEqual(store.tasks.count, 1)
    }

    func testSlashCommandDoesNotCreateTask() {
        processor.apply(ev(.userPromptSubmit, prompt: "/clear"))
        processor.apply(ev(.userPromptSubmit, prompt: "  /rename Foo  "))
        XCTAssertEqual(store.tasks.count, 0)
    }

    func testEmptyPromptDoesNotCreateTask() {
        processor.apply(ev(.userPromptSubmit, prompt: "   \n"))
        XCTAssertEqual(store.tasks.count, 0)
    }

    func testSlashCommandOnExistingTaskDoesNotRetitle() {
        processor.apply(ev(.userPromptSubmit, prompt: "Real prompt"))
        processor.apply(ev(.userPromptSubmit, prompt: "/compact"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.title, "Real prompt")
    }

    func testPinnedTitleIsNotOverwrittenByPrompt() {
        processor.apply(ev(.userPromptSubmit, prompt: "First"))
        let id = store.task(claudeSessionId: "S1")!.id
        store.setTitle(id: id, "Renamed", pinned: true)
        processor.apply(ev(.userPromptSubmit, prompt: "whatever"))
        XCTAssertEqual(store.task(id: id)?.title, "Renamed")
    }

    // MARK: Completion

    func testCompletionPhrasesMarkDone() {
        for phrase in ["Tarefa concluída", "ok, task done!", "TASK COMPLETE", "tarefa concluida"] {
            store = TaskStore(persistence: nil); processor = InboxProcessor(store: store)
            processor.apply(ev(.userPromptSubmit, prompt: "Start work"))
            processor.apply(ev(.userPromptSubmit, prompt: phrase))
            XCTAssertEqual(store.task(claudeSessionId: "S1")?.status, .done, phrase)
        }
    }

    func testPhraseInsideSentenceStillCompletes() {
        processor.apply(ev(.userPromptSubmit, prompt: "Start work"))
        processor.apply(ev(.userPromptSubmit, prompt: "is the task done yet? keep going"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.status, .done)
    }

    func testNonCompletionPhraseStaysOpen() {
        processor.apply(ev(.userPromptSubmit, prompt: "Start work"))
        processor.apply(ev(.userPromptSubmit, prompt: "tasks are done"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.status, .open)
    }

    func testCompletionPhraseWithoutTaskCreatesNothing() {
        processor.apply(ev(.userPromptSubmit, prompt: "task done"))
        XCTAssertEqual(store.tasks.count, 0)
    }

    func testSessionEndMarksDoneAndClearsActivity() {
        processor.apply(ev(.userPromptSubmit, prompt: "Start work"))
        processor.apply(ev(.sessionEnd))
        let t = store.task(claudeSessionId: "S1")
        XCTAssertEqual(t?.status, .done)
        XCTAssertNil(t?.activity)
    }

    func testSessionEndForUnknownSessionIsNoop() {
        processor.apply(ev(.sessionEnd))
        XCTAssertEqual(store.tasks.count, 0)
    }

    // MARK: Activity from Stop and Notification

    func testStopMarksFinished() {
        processor.apply(ev(.userPromptSubmit, prompt: "Start work"))
        processor.apply(ev(.stop))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.activity, .finished)
    }

    func testNotificationMarksWaitingInput() {
        processor.apply(ev(.userPromptSubmit, prompt: "Start work"))
        processor.apply(ev(.notification, message: "Claude needs your permission to use Bash"))
        XCTAssertEqual(store.task(claudeSessionId: "S1")?.activity, .waitingInput)
    }

    func testActivityEventsIgnoreUnknownAndDoneSessions() {
        processor.apply(ev(.stop))
        processor.apply(ev(.notification))
        XCTAssertEqual(store.tasks.count, 0)
        processor.apply(ev(.userPromptSubmit, prompt: "Start work"))
        processor.apply(ev(.sessionEnd))
        processor.apply(ev(.notification))
        XCTAssertNil(store.task(claudeSessionId: "S1")?.activity)
    }
}
