import SwiftUI

struct AddRuleView: View {

    /// Pass an existing rule to edit it; `nil` to create a new one.
    let existing: IndexRule?
    let onSave: (IndexRule) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var path: String = ""
    @State private var isRecursive: Bool = false
    @State private var includeHidden: Bool = false
    @State private var extensionInput: String = ""  // comma-separated
    @State private var fileCountEstimate: Int? = nil
    @State private var isEstimating = false
    @State private var showLargeWarning = false
    @State private var pendingRule: IndexRule? = nil

    private var isEditing: Bool { existing != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            Text(isEditing ? "Edit Directory" : "Add Directory")
                .font(.headline)
                .padding([.top, .horizontal])

            Divider().padding(.top, 8)

            Form {
                // Directory picker
                Section {
                    HStack {
                        TextField("Path", text: $path)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)

                        Button("Choose…") { pickDirectory() }
                    }
                } header: { Text("Directory") }

                // Options
                Section {
                    Toggle("Index subdirectories recursively", isOn: $isRecursive)
                    Toggle("Include hidden files and folders", isOn: $includeHidden)
                } header: { Text("Options") }

                // File types
                Section {
                    TextField("e.g. pdf, swift, png  (leave blank for all types)", text: $extensionInput)
                        .textFieldStyle(.roundedBorder)
                } header: { Text("File Types") } footer: {
                    Text("Comma-separated extensions without the dot. Leave blank to index every file type.")
                        .foregroundStyle(.secondary)
                }

                // File count estimate
                if let count = fileCountEstimate {
                    Section {
                        HStack {
                            Image(systemName: count > 1_000 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(count > 1_000 ? .orange : .green)
                            Text(count > 1_000
                                 ? "~\(count)+ files — this will index a large number of files."
                                 : "~\(count) files will be indexed.")
                                .foregroundStyle(count > 1_000 ? .orange : .primary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Action buttons
            HStack {
                Button("Estimate File Count") { runEstimate() }
                    .disabled(path.isEmpty || isEstimating)

                if isEstimating {
                    ProgressView().scaleEffect(0.75)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Add") { trySave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(path.isEmpty)
            }
            .padding()
        }
        .frame(width: 480)
        .onAppear { populate() }
        .alert("Large Index Warning", isPresented: $showLargeWarning) {
            Button("Index Anyway", role: .destructive) {
                if let rule = pendingRule { commit(rule) }
            }
            Button("Cancel", role: .cancel) { pendingRule = nil }
        } message: {
            Text("This directory contains more than 1,000 files. Indexing it may take a while. Continue?")
        }
    }

    // MARK: – Setup

    private func populate() {
        guard let rule = existing else { return }
        path = rule.path
        isRecursive = rule.isRecursive
        includeHidden = rule.includeHidden
        extensionInput = rule.allowedExtensions.joined(separator: ", ")
    }

    // MARK: – Directory picker

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a directory to index"

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            fileCountEstimate = nil
        }
    }

    // MARK: – Estimate

    private func runEstimate() {
        guard !path.isEmpty else { return }
        isEstimating = true
        fileCountEstimate = nil
        let rule = buildRule()
        Task {
            let count = await IndexManager.shared.estimatedFileCount(for: rule)
            await MainActor.run {
                fileCountEstimate = count
                isEstimating = false
            }
        }
    }

    // MARK: – Save

    private func trySave() {
        let rule = buildRule()

        // If we already know the count, use it; otherwise let it through without warning.
        if let count = fileCountEstimate, count > 1_000 {
            pendingRule = rule
            showLargeWarning = true
            return
        }

        // Unknown count — run a quick background check
        Task {
            let count = await IndexManager.shared.estimatedFileCount(for: rule)
            await MainActor.run {
                fileCountEstimate = count
                if count > 1_000 {
                    pendingRule = rule
                    showLargeWarning = true
                } else {
                    commit(rule)
                }
            }
        }
    }

    private func commit(_ rule: IndexRule) {
        onSave(rule)
        dismiss()
    }

    // MARK: – Helpers

    private func buildRule() -> IndexRule {
        let extensions = extensionInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        return IndexRule(
            id: existing?.id ?? UUID(),
            path: path,
            isRecursive: isRecursive,
            allowedExtensions: extensions,
            includeHidden: includeHidden
        )
    }
}
