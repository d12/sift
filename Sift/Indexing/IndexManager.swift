import Foundation
import CoreServices

extension Notification.Name {
    static let excessiveReindexingDetected = Notification.Name("excessiveReindexingDetected")
    static let indexingStatusChanged       = Notification.Name("indexingStatusChanged")
}

/// Central actor that owns the search index, file watchers, and coordinates indexing.
actor IndexManager {

    static let shared = IndexManager()

    // MARK: – State

    private(set) var isIndexing = false
    private var db: SearchIndex?
    /// Exposed outside actor isolation for synchronous main-thread search.
    /// Written once in initialize(); DatabaseQueue handles its own thread safety.
    nonisolated(unsafe) private var _searchDB: SearchIndex?
    private var watchers: [UUID: FileWatcher] = [:]
    private let worker = IndexWorker()
    private let monitor = ResourceMonitor()

    /// Per-path throttle: skip re-indexing the same file within this window.
    private var lastIndexed: [String: Date] = [:]
    private let throttleInterval: TimeInterval = 3.0

    // MARK: – Lifecycle

    func initialize() async {
        do {
            db = try SearchIndex()
            _searchDB = db   // make available to the synchronous search path
        } catch {
            print("[Sift] SearchIndex init failed: \(error)")
            return
        }
        await refreshWatchers()
        await reindexAll()
    }

    // MARK: – Search

    /// Synchronous, non-isolated search called directly from the main thread.
    /// Skips Task scheduling and actor hops entirely; the underlying
    /// DatabaseQueue.read is thread-safe and takes < 1 ms on a small index.
    nonisolated func searchSync(query: String, typeFilter: TypeFilter?) -> [SearchResult] {
        guard let db = _searchDB,
              !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return (try? db.search(query: query, extensions: typeFilter?.extensions)) ?? []
    }

    /// Async search kept for internal / background use.
    func search(query: String, typeFilter: TypeFilter?) async -> [SearchResult] {
        guard let db, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        do {
            return try db.search(query: query, extensions: typeFilter?.extensions)
        } catch {
            print("[Sift] Search error: \(error)")
            return []
        }
    }

    // MARK: – Indexing

    func reindexAll() async {
        guard let db else { return }
        setIndexing(true)
        let rules = await MainActor.run { AppSettings.shared.indexRules }
        for rule in rules {
            await worker.index(rule: rule, db: db)
        }
        setIndexing(false)
    }

    func reindex(rule: IndexRule) async {
        guard let db else { return }
        setIndexing(true)
        await worker.index(rule: rule, db: db)
        setIndexing(false)
    }

    func removeIndex(for rule: IndexRule) async {
        try? db?.deleteByRule(ruleId: rule.id.uuidString)
        monitor.reset(forRoot: rule.path)
    }

    func estimatedFileCount(for rule: IndexRule) async -> Int {
        await worker.estimatedFileCount(for: rule)
    }

    // MARK: – Watcher management

    /// Call whenever `AppSettings.indexRules` changes so watchers stay in sync.
    func refreshWatchers() async {
        let rules = await MainActor.run { AppSettings.shared.indexRules }
        let currentIds = Set(rules.map { $0.id })

        // Stop watchers for removed rules
        for id in watchers.keys where !currentIds.contains(id) {
            watchers[id]?.stop()
            watchers.removeValue(forKey: id)
        }

        // Start watchers for new rules
        for rule in rules where watchers[rule.id] == nil {
            let ruleId = rule.id
            let rulePath = rule.path
            let watcher = FileWatcher(paths: [rule.path]) { [weak self] path, flags in
                Task { await self?.handleEvent(path: path, flags: flags, ruleId: ruleId, rootPath: rulePath) }
            }
            watchers[rule.id] = watcher
        }
    }

    // MARK: – Event handling

    private func handleEvent(
        path: String,
        flags: FSEventStreamEventFlags,
        ruleId: UUID,
        rootPath: String
    ) async {
        let shouldProceed = monitor.recordEvent(forRoot: rootPath)

        if monitor.isExcessive(forRoot: rootPath) {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .excessiveReindexingDetected,
                    object: nil,
                    userInfo: ["path": rootPath]
                )
            }
            return
        }

        guard shouldProceed, let db else { return }

        // Throttle repeated events on the same path
        let now = Date()
        if let last = lastIndexed[path], now.timeIntervalSince(last) < throttleInterval { return }
        lastIndexed[path] = now

        let isRemoved = flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0

        if isRemoved {
            try? db.delete(path: path)
            return
        }

        // Find the matching rule so we can apply its filters
        let rules = await MainActor.run { AppSettings.shared.indexRules }
        guard let rule = rules.first(where: { $0.id == ruleId }) else { return }

        if let file = worker.makeIndexedFile(path: path, rule: rule) {
            try? db.upsert(file)
        }
    }

    // MARK: – Helpers

    private func setIndexing(_ value: Bool) {
        isIndexing = value
        let v = value
        Task { @MainActor in
            NotificationCenter.default.post(name: .indexingStatusChanged, object: nil,
                                            userInfo: ["isIndexing": v])
        }
    }
}
