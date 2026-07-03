import SwiftUI

struct IndexingSettingsView: View {

    @EnvironmentObject private var settings: AppSettings
    @State private var showAddRule = false
    @State private var ruleToEdit: IndexRule?
    @State private var isReindexing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ruleList
            Divider()
            bottomBar
        }
        .sheet(isPresented: $showAddRule) {
            AddRuleView(existing: nil) { newRule in
                settings.add(rule: newRule)
                Task { await IndexManager.shared.refreshWatchers(); await IndexManager.shared.reindex(rule: newRule) }
            }
        }
        .sheet(item: $ruleToEdit) { rule in
            AddRuleView(existing: rule) { updated in
                settings.update(rule: updated)
                Task { await IndexManager.shared.refreshWatchers(); await IndexManager.shared.reindex(rule: updated) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .indexingStatusChanged)) { note in
            isReindexing = note.userInfo?["isIndexing"] as? Bool ?? false
        }
    }

    // MARK: – Rule list

    @ViewBuilder
    private var ruleList: some View {
        if settings.indexRules.isEmpty {
            emptyState
        } else {
            List {
                ForEach(settings.indexRules) { rule in
                    RuleRow(rule: rule)
                        .contextMenu {
                            Button("Edit…") { ruleToEdit = rule }
                            Button("Re-index Now") {
                                Task { await IndexManager.shared.reindex(rule: rule) }
                            }
                            Divider()
                            Button("Remove", role: .destructive) { remove(rule) }
                        }
                        .onTapGesture(count: 2) { ruleToEdit = rule }
                }
                .onDelete { offsets in
                    offsets.map { settings.indexRules[$0] }.forEach(remove)
                }
            }
            .listStyle(.inset)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("No indexed directories")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Add a directory to start indexing files.")
                .foregroundStyle(.tertiary)
            Button("Add Directory…") { showAddRule = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Bottom bar

    private var bottomBar: some View {
        HStack {
            Button { showAddRule = true } label: {
                Image(systemName: "plus")
            }
            .help("Add a directory to index")

            Button {
                if let selected = settings.indexRules.first {
                    remove(selected)
                }
            } label: {
                Image(systemName: "minus")
            }
            .disabled(settings.indexRules.isEmpty)
            .help("Remove selected directory")

            Spacer()

            if isReindexing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Indexing…").foregroundStyle(.secondary).font(.caption)
                }
            }

            Button("Reindex All") {
                Task { await IndexManager.shared.reindexAll() }
            }
            .disabled(settings.indexRules.isEmpty || isReindexing)
            .controlSize(.small)
        }
        .padding(8)
    }

    // MARK: – Actions

    private func remove(_ rule: IndexRule) {
        settings.remove(rule: rule)
        Task {
            await IndexManager.shared.removeIndex(for: rule)
            await IndexManager.shared.refreshWatchers()
        }
    }
}

// MARK: – Rule row

private struct RuleRow: View {
    let rule: IndexRule

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.path)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    if rule.isRecursive   { tag("Recursive") }
                    if rule.includeHidden { tag("Hidden files") }
                    tag(rule.extensionSummary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func tag(_ label: String) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
    }
}
