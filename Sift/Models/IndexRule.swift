import Foundation

/// A rule describing a directory to be indexed by Sift.
struct IndexRule: Codable, Identifiable, Sendable {
    let id: UUID
    /// Absolute path to the directory.
    var path: String
    /// Recurse into subdirectories.
    var isRecursive: Bool
    /// File extensions to index. Empty = index all types.
    var allowedExtensions: [String]
    /// Include dot-files and dot-directories.
    var includeHidden: Bool

    init(
        id: UUID = UUID(),
        path: String,
        isRecursive: Bool = false,
        allowedExtensions: [String] = [],
        includeHidden: Bool = false
    ) {
        self.id = id
        self.path = path
        self.isRecursive = isRecursive
        self.allowedExtensions = allowedExtensions
        self.includeHidden = includeHidden
    }

    /// Human-readable summary of what file types are indexed.
    var extensionSummary: String {
        if allowedExtensions.isEmpty { return "All types" }
        return allowedExtensions.map { $0.uppercased() }.joined(separator: ", ")
    }
}
