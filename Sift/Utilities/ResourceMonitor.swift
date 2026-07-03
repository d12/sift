import Foundation

/// Tracks file-system event rates per root path and detects runaway directories.
///
/// Thread-safe – all mutations happen inside a `Lock`.
final class ResourceMonitor: Sendable {

    // MARK: – Configuration

    /// Number of events within `windowSeconds` that triggers a warning.
    static let eventThreshold = 200
    static let windowSeconds: TimeInterval = 10

    // MARK: – State

    private struct Entry {
        var timestamps: [Date] = []
        var pausedUntil: Date?
    }

    private let lock = NSLock()
    private nonisolated(unsafe) var entries: [String: Entry] = [:]

    // MARK: – Public API

    /// Record a file-system event for the given path's watched root.
    /// Returns `true` when the event should be processed (not rate-limited).
    @discardableResult
    func recordEvent(forRoot root: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var entry = entries[root, default: Entry()]
        let now = Date()

        // Drop events older than the window
        entry.timestamps = entry.timestamps.filter {
            now.timeIntervalSince($0) < Self.windowSeconds
        }
        entry.timestamps.append(now)

        let excessive = entry.timestamps.count >= Self.eventThreshold

        if excessive && entry.pausedUntil == nil {
            // Pause for 5 minutes before warning again
            entry.pausedUntil = now.addingTimeInterval(300)
        } else if !excessive {
            entry.pausedUntil = nil
        }

        entries[root] = entry
        return !excessive
    }

    /// Returns `true` when the directory is currently considered excessively active.
    func isExcessive(forRoot root: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[root] else { return false }
        let now = Date()
        let recent = entry.timestamps.filter { now.timeIntervalSince($0) < Self.windowSeconds }
        return recent.count >= Self.eventThreshold
    }

    /// Current event rate (events per second) for the given root.
    func eventRate(forRoot root: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[root] else { return 0 }
        let now = Date()
        let recent = entry.timestamps.filter { now.timeIntervalSince($0) < Self.windowSeconds }
        return Double(recent.count) / Self.windowSeconds
    }

    /// Resets tracking state for a root (e.g., when the user removes the rule).
    func reset(forRoot root: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: root)
    }
}
