import Foundation

public final class InboxDrainer: @unchecked Sendable {
    public static let inboxFileName = "inbox.jsonl"
    private static let processingPrefix = "inbox.processing-"

    private let directory: URL
    private let settleDelay: TimeInterval
    private let handler: @Sendable ([InboxEvent]) -> Void
    private let queue = DispatchQueue(label: "stasks.inbox", qos: .utility)
    private var watcher: FileWatcher?
    private var timer: DispatchSourceTimer?
    private let drainLock = NSLock()

    public init(directory: URL, settleDelay: TimeInterval = 0.15, handler: @escaping @Sendable ([InboxEvent]) -> Void) {
        self.directory = directory
        self.settleDelay = settleDelay
        self.handler = handler
    }

    public func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let w = FileWatcher(url: directory, queue: queue) { [weak self] in self?.drainNow() }
        watcher = w
        w.start()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 3)
        t.setEventHandler { [weak self] in self?.drainNow() }
        timer = t
        t.resume()
        queue.async { [self] in drainNow() }
    }

    public func stop() {
        watcher?.stop(); watcher = nil
        timer?.cancel(); timer = nil
    }

    /// Safe to call from any thread; drains are serialized by an internal lock.
    public func drainNow() {
        drainLock.lock()
        defer { drainLock.unlock() }

        let fm = FileManager.default
        var events: [InboxEvent] = []

        // 1. Leftovers from a previous crash.
        if let names = try? fm.contentsOfDirectory(atPath: directory.path) {
            for name in names where name.hasPrefix(Self.processingPrefix) {
                events.append(contentsOf: consume(directory.appendingPathComponent(name)))
            }
        }

        // 2. Current inbox: rename, settle, consume.
        let inbox = directory.appendingPathComponent(Self.inboxFileName)
        if fm.fileExists(atPath: inbox.path) {
            let processing = directory.appendingPathComponent("\(Self.processingPrefix)\(UUID().uuidString).jsonl")
            do {
                try fm.moveItem(at: inbox, to: processing)
                if settleDelay > 0 { Thread.sleep(forTimeInterval: settleDelay) }
                events.append(contentsOf: consume(processing))
            } catch {
                Log.inbox.error("rename failed: \(error.localizedDescription)")
            }
        }

        if !events.isEmpty {
            Log.inbox.info("drained \(events.count) event(s)")
            handler(events)
        }
    }

    /// Reads and parses a processing file, deleting it only after a successful read.
    /// A read failure (e.g. permission denied) is logged and leaves the file in place
    /// so the next drain retries it, instead of losing the events silently.
    private func consume(_ url: URL) -> [InboxEvent] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Log.inbox.error("read failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return []
        }
        try? FileManager.default.removeItem(at: url)
        return InboxParser.parse(data: data)
    }
}
