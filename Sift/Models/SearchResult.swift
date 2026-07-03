import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SearchResult: Identifiable, Sendable {
    let id: String       // file path used as stable identifier
    let name: String     // display name (no extension)
    let path: String     // full absolute path
    let url: URL
    let fileExtension: String

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    var fileTypeLabel: String {
        if fileExtension.isEmpty { return "File" }
        if let type = UTType(filenameExtension: fileExtension),
           let desc = type.localizedDescription {
            return desc
        }
        return fileExtension.uppercased()
    }
}
