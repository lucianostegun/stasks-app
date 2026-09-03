import Foundation

/// Tails Claude Code session transcripts (`.jsonl`) for `/rename` custom-title lines,
/// one `FileWatcher` per watched session, reading only newly appended bytes.
public final class TranscriptWatcher: @unchecked Sendable {
    private struct Entry { let watcher: FileWatcher; var offset: UInt64 }

    private let onTitle: @Sendable (String, String) -> Void
    private let queue = DispatchQueue(label: "stasks.transcript", qos: .utility)
    private var entries: [String: Entry] = [:]

    public init(onTitle: @escaping @Sendable (_ sessionId: String, _ title: String) -> Void) {
        self.onTitle = onTitle
    }

    public func watch(sessionId: String, path: String) {
        queue.async { [self] in
            guard entries[sessionId] == nil, !path.isEmpty else { return }
            let url = URL(fileURLWithPath: path)
            let w = FileWatcher(url: url, queue: queue) { [weak self] in self?.readNew(sessionId: sessionId, url: url) }
            entries[sessionId] = Entry(watcher: w, offset: 0)
            readNew(sessionId: sessionId, url: url)
            w.start()
        }
    }

    public func unwatch(sessionId: String) {
        queue.async { [self] in
            entries[sessionId]?.watcher.stop()
            entries[sessionId] = nil
        }
    }

    public func unwatchAll() {
        queue.async { [self] in
            entries.values.forEach { $0.watcher.stop() }
            entries.removeAll()
        }
    }

    private func readNew(sessionId: String, url: URL) {
        guard var entry = entries[sessionId], let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > entry.offset else { return }
        try? handle.seek(toOffset: entry.offset)
        guard let data = try? handle.readToEnd() else { return }
        entry.offset = size
        entries[sessionId] = entry
        if let title = TranscriptParser.latestCustomTitle(in: data) {
            Log.transcript.info("custom title for \(sessionId, privacy: .public)")
            onTitle(sessionId, title)
        }
    }
}
