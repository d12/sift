import Foundation

/// Scans directories and feeds files into `SearchIndex` on a background task.
/// CPU-friendly: uses `.background` priority and yields between batches.
struct IndexWorker: Sendable {

    private static let batchSize = 500

    /// Extensions that represent self-contained bundles.
    /// We index these as single items and never recurse inside them.
    /// This is extension-based (not isPackageKey) because apps on the sealed
    /// system volume (/System/Applications) often have isPackage = false.
    private static let bundleExtensions: Set<String> = [
        "app", "bundle", "plugin", "kext", "xpc", "prefPane",
        "qlgenerator", "mdimporter", "appex",
    ]

    // MARK: – Full rule index

    func index(rule: IndexRule, db: SearchIndex) async {
        try? db.deleteByRule(ruleId: rule.id.uuidString)

        let url = URL(fileURLWithPath: rule.path)
        let options = enumerationOptions(for: rule)

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: options
        ) else { return }

        await Task(priority: .background) {
            var batch: [IndexedFile] = []
            batch.reserveCapacity(Self.batchSize)

            while let fileURL = enumerator.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()

                if Self.bundleExtensions.contains(ext) {
                    // Treat the bundle as one item; never look inside it.
                    enumerator.skipDescendants()

                    if !rule.allowedExtensions.isEmpty, !rule.allowedExtensions.contains(ext) { continue }
                    if let file = makeFile(url: fileURL, ext: ext, ruleId: rule.id.uuidString) {
                        batch.append(file)
                    }
                } else {
                    guard let values = try? fileURL.resourceValues(
                        forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
                    ), values.isRegularFile == true else { continue }

                    if !rule.allowedExtensions.isEmpty, !rule.allowedExtensions.contains(ext) { continue }

                    let name = fileURL.deletingPathExtension().lastPathComponent
                    batch.append(IndexedFile(
                        path: fileURL.path,
                        name: name,
                        ext: ext,
                        size: Int64(values.fileSize ?? 0),
                        modifiedAt: (values.contentModificationDate ?? .distantPast).timeIntervalSince1970,
                        ruleId: rule.id.uuidString,
                        acronym: Self.makeAcronym(from: name)
                    ))
                }

                if batch.count >= Self.batchSize {
                    try? db.bulkUpsert(batch)
                    batch.removeAll(keepingCapacity: true)
                    await Task.yield()
                }
            }

            if !batch.isEmpty {
                try? db.bulkUpsert(batch)
            }
        }.value
    }

    // MARK: – File count preview (early-exits at 1 001 for performance)

    func estimatedFileCount(for rule: IndexRule) async -> Int {
        let url = URL(fileURLWithPath: rule.path)
        let options = enumerationOptions(for: rule)

        return await Task(priority: .background) {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: options
            ) else { return 0 }

            var count = 0
            while let fileURL = enumerator.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()

                if Self.bundleExtensions.contains(ext) {
                    enumerator.skipDescendants()
                    if !rule.allowedExtensions.isEmpty, !rule.allowedExtensions.contains(ext) { continue }
                    count += 1
                } else {
                    guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                          vals.isRegularFile == true else { continue }
                    if !rule.allowedExtensions.isEmpty, !rule.allowedExtensions.contains(ext) { continue }
                    count += 1
                }

                if count > 1_000 { return count }
            }
            return count
        }.value
    }

    // MARK: – Single-file helpers (called from FSEvents handler)

    func makeIndexedFile(path: String, rule: IndexRule) -> IndexedFile? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        if !rule.includeHidden, url.lastPathComponent.hasPrefix(".") { return nil }
        if !rule.allowedExtensions.isEmpty, !rule.allowedExtensions.contains(ext) { return nil }

        if Self.bundleExtensions.contains(ext) {
            return makeFile(url: url, ext: ext, ruleId: rule.id.uuidString)
        }

        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        ), values.isRegularFile == true else { return nil }

        let name = url.deletingPathExtension().lastPathComponent
        return IndexedFile(
            path: path,
            name: name,
            ext: ext,
            size: Int64(values.fileSize ?? 0),
            modifiedAt: (values.contentModificationDate ?? .distantPast).timeIntervalSince1970,
            ruleId: rule.id.uuidString,
            acronym: Self.makeAcronym(from: name)
        )
    }

    // MARK: – Private helpers

    private func makeFile(url: URL, ext: String, ruleId: String) -> IndexedFile? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let name = url.deletingPathExtension().lastPathComponent
        return IndexedFile(
            path: url.path,
            name: name,
            ext: ext,
            size: Int64(values?.fileSize ?? 0),
            modifiedAt: (values?.contentModificationDate ?? .distantPast).timeIntervalSince1970,
            ruleId: ruleId,
            acronym: Self.makeAcronym(from: name)
        )
    }

    /// First letter of each word, lowercased. "Visual Studio Code" → "vsc".
    /// Stored as a separate FTS5 column so prefix queries on initials
    /// (e.g. "vs code") match multi-word names naturally.
    private static func makeAcronym(from name: String) -> String {
        name.split { !$0.isLetter }
            .compactMap { $0.first.map(String.init) }
            .joined()
            .lowercased()
    }

    private func enumerationOptions(for rule: IndexRule) -> FileManager.DirectoryEnumerationOptions {
        var opts: FileManager.DirectoryEnumerationOptions = []
        if !rule.isRecursive   { opts.insert(.skipsSubdirectoryDescendants) }
        if !rule.includeHidden { opts.insert(.skipsHiddenFiles) }
        // Keep as belt-and-suspenders for apps where the OS does set the package flag.
        opts.insert(.skipsPackageDescendants)
        return opts
    }
}
