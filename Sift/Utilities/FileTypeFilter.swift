import Foundation
import UniformTypeIdentifiers

/// Parsed result from a user query that may contain a type-filter prefix.
struct TypeFilter: Sendable {
    let extensions: [String]
}

enum FileTypeFilter {

    // MARK: – Prefix → extension mapping

    private static let prefixMap: [String: [String]] = [
        "app":    ["app"],
        "pdf":    ["pdf"],
        "doc":    ["doc", "docx"],
        "xls":    ["xls", "xlsx"],
        "ppt":    ["ppt", "pptx"],
        "image":  ["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp", "svg"],
        "img":    ["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp", "svg"],
        "photo":  ["jpg", "jpeg", "png", "heic", "raw", "dng"],
        "video":  ["mp4", "mov", "avi", "mkv", "m4v", "webm", "wmv"],
        "audio":  ["mp3", "aac", "wav", "flac", "m4a", "ogg", "aiff"],
        "music":  ["mp3", "aac", "wav", "flac", "m4a", "ogg", "aiff"],
        "text":   ["txt", "md", "markdown", "rtf"],
        "code":   ["swift", "py", "js", "ts", "html", "css", "java", "c", "cpp", "h",
                   "go", "rs", "rb", "php", "sh", "kt", "cs", "m", "json", "yaml", "toml"],
        "zip":    ["zip", "tar", "gz", "bz2", "7z", "rar", "xz"],
        "font":   ["ttf", "otf", "woff", "woff2"],
        "model":  ["obj", "fbx", "stl", "usdz", "gltf", "glb"],
    ]

    // MARK: – Public API

    /// Parse a raw query string into an optional `TypeFilter` and the clean search term.
    ///
    /// - Examples:
    ///   - `"pdf: annual report"` → `(TypeFilter(["pdf"]), "annual report")`
    ///   - `"app: xcode"` → `(TypeFilter(["app"]), "xcode")`
    ///   - `"hello world"` → `(nil, "hello world")`
    static func parse(query raw: String) -> (TypeFilter?, String) {
        let colonRange = raw.range(of: ":")
        guard let range = colonRange else { return (nil, raw) }

        let prefix = String(raw[raw.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        let rest = String(raw[range.upperBound...])
            .trimmingCharacters(in: .whitespaces)

        if let exts = prefixMap[prefix] {
            return (TypeFilter(extensions: exts), rest)
        }

        // Check if prefix itself is a file extension (e.g. "swift: parser")
        let ext = prefix
        if !ext.isEmpty && ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return (TypeFilter(extensions: [ext]), rest)
        }

        return (nil, raw)
    }

    // MARK: – FTS5 query preparation

    /// Sanitise a search term for use in an FTS5 MATCH expression,
    /// returning a prefix-match query (e.g. `"foo* AND bar*"`).
    static func prepareFTSQuery(_ term: String) -> String {
        // Strip characters that are special in FTS5
        let ftsSpecial = CharacterSet(charactersIn: "\"()^*:-")
        let sanitised = term.unicodeScalars
            .map { ftsSpecial.contains($0) ? " " : Character($0) }
            .map(String.init)
            .joined()

        let tokens = sanitised
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return "" }
        return tokens.map { "\($0)*" }.joined(separator: " AND ")
    }
}
