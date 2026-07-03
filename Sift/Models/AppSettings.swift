import Foundation
import Combine

/// Persists and publishes all user-facing preferences.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var indexRules: [IndexRule] {
        didSet { save() }
    }

    private let rulesKey = "indexRules"

    /// Directories indexed on a fresh install.
    private static let defaultRules: [IndexRule] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            IndexRule(path: "/Applications",        isRecursive: false),
            IndexRule(path: "/System/Applications", isRecursive: false),
            IndexRule(path: "\(home)/Applications", isRecursive: false),
        ]
        // Filter out paths that don't exist on this machine (~/Applications is optional).
        .filter { FileManager.default.fileExists(atPath: $0.path) }
    }()

    private init() {
        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let rules = try? JSONDecoder().decode([IndexRule].self, from: data) {
            indexRules = rules
        } else {
            // First launch — seed with the standard application directories.
            indexRules = Self.defaultRules
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(indexRules) else { return }
        UserDefaults.standard.set(data, forKey: rulesKey)
    }

    func add(rule: IndexRule) {
        indexRules.append(rule)
    }

    func update(rule: IndexRule) {
        guard let idx = indexRules.firstIndex(where: { $0.id == rule.id }) else { return }
        indexRules[idx] = rule
    }

    func remove(rule: IndexRule) {
        indexRules.removeAll { $0.id == rule.id }
    }
}
