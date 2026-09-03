import Foundation

/// Watches a file or directory vnode. Fires `onChange` on write/extend/rename/delete.
/// Re-opens the descriptor when the path is deleted and recreated.
public final class FileWatcher: @unchecked Sendable {
    private let url: URL
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var retryTimer: DispatchSourceTimer?

    public init(url: URL, queue: DispatchQueue = DispatchQueue(label: "stasks.filewatcher", qos: .utility),
                onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.queue = queue
        self.onChange = onChange
    }

    public func start() {
        queue.async { [self] in open() }
    }

    public func stop() {
        queue.async { [self] in
            source?.cancel(); source = nil
            retryTimer?.cancel(); retryTimer = nil
        }
    }

    private func open() {
        retryTimer?.cancel(); retryTimer = nil
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { scheduleRetry(); return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete, .attrib], queue: queue)
        let capturedFd = fd
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            self.onChange()
            if flags.contains(.delete) || flags.contains(.rename) {
                src.cancel()
                self.source = nil
                self.open()
            }
        }
        src.setCancelHandler { Darwin.close(capturedFd) }
        source = src
        src.resume()
        // Catch up immediately: content may have been written between the previous descriptor
        // becoming invalid (a delete/rename that triggered this reopen, or the path not
        // existing yet on a scheduleRetry recovery) and this (re)open completing. No further
        // vnode event will ever fire for changes that already happened before the new kevent
        // was armed, so without this, those changes would only surface on the next unrelated
        // write. This also covers the very first open from start(): the small window between
        // start() returning and the kevent actually being armed on the queue means a caller
        // that mutates the watched path right away could otherwise race the same way. Any
        // caller's own separate initial read becomes redundant here, but harmless.
        onChange()
    }

    private func scheduleRetry() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1)
        t.setEventHandler { [weak self] in self?.open() }
        retryTimer = t
        t.resume()
    }
}
