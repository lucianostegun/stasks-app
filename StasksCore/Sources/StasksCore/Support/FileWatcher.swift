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
    }

    private func scheduleRetry() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1)
        t.setEventHandler { [weak self] in self?.open() }
        retryTimer = t
        t.resume()
    }
}
