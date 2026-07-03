import Foundation
import CoreServices

/// Wraps an FSEventStream to watch one or more directory paths for changes.
final class FileWatcher: @unchecked Sendable {

    typealias EventCallback = @Sendable (_ path: String, _ flags: FSEventStreamEventFlags) -> Void

    private var stream: FSEventStreamRef?
    fileprivate let callback: EventCallback
    private let paths: [String]
    /// Seconds to coalesce events before delivering them.
    private let latency: TimeInterval

    init(paths: [String], latency: TimeInterval = 1.5, callback: @escaping EventCallback) {
        self.paths = paths
        self.latency = latency
        self.callback = callback
        start()
    }

    deinit { stop() }

    // MARK: – Start / stop

    private func start() {
        guard !paths.isEmpty else { return }

        // Retain `self` so the C callback can reach it.
        let selfPtr = Unmanaged.passRetained(self)

        var ctx = FSEventStreamContext(
            version: 0,
            info: selfPtr.toOpaque(),
            retain: nil,
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<FileWatcher>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )

        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileWatcherCallback,
            &ctx,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            createFlags
        )

        guard let s = stream else {
            selfPtr.release()   // release the retain we took above since stream creation failed
            return
        }

        FSEventStreamScheduleWithRunLoop(s, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(s)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }
}

// MARK: – C callback (file-scope, no captures)

private let fileWatcherCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
    guard let info else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self)

    for i in 0..<numEvents {
        if let path = paths[i] as? String {
            watcher.callback(path, eventFlags[i])
        }
    }
}
