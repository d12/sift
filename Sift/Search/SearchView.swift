import SwiftUI

struct SearchView: View {

    /// Called when the view wants to dismiss the search panel.
    let dismiss: () -> Void

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    private let maxResults = 50

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            if !results.isEmpty {
                Divider().opacity(0.3)
                resultsList
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .animation(.spring(duration: 0.2), value: results.count)
        .frame(width: 680)   // match the panel width so the text field fills the bar
        .onAppear {
            // Defer one run-loop cycle; the window must be key before @FocusState
            // can direct focus to the text field.
            Task { @MainActor in
                searchFocused = true
            }
        }
        .onChange(of: query) { _, newValue in
            // Synchronous search: DatabaseQueue.read is thread-safe and finishes
            // in < 1 ms on a small index, so no Task, debounce, or actor hop needed.
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                results = []
                selectedIndex = 0
                return
            }
            let (typeFilter, term) = FileTypeFilter.parse(query: trimmed)
            results = IndexManager.shared.searchSync(query: term, typeFilter: typeFilter)
            selectedIndex = 0
        }
    }

    // MARK: – Input row

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 22)

            TextField("Search files…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .focused($searchFocused)
                .onKeyPress(.escape)    { dismiss(); return .handled }
                .onKeyPress(.upArrow)   { moveSelection(by: -1); return .handled }
                .onKeyPress(.downArrow) { moveSelection(by:  1); return .handled }
                .onKeyPress(.return)    { openSelected(); return .handled }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    // MARK: – Results list

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                // VStack (not LazyVStack): with ≤50 results the lazy variant
                // can fail to re-render rows whose IDs change while the count
                // stays the same, causing stale results to stick on screen.
                VStack(spacing: 0) {
                    ForEach(Array(results.prefix(maxResults).enumerated()), id: \.element.id) { index, result in
                        ResultRowView(result: result, isSelected: index == selectedIndex)
                            .id(result.id)
                            .onTapGesture { open(result) }
                            .onHover { hovering in
                                if hovering { selectedIndex = index }
                            }
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 420)
            .onChange(of: selectedIndex) { _, idx in
                guard idx < results.count else { return }
                withAnimation { proxy.scrollTo(results[idx].id, anchor: .center) }
            }
        }
    }

    // MARK: – Actions

    private func moveSelection(by delta: Int) {
        let count = min(results.count, maxResults)
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func openSelected() {
        guard selectedIndex < results.count else { return }
        open(results[selectedIndex])
    }

    private func open(_ result: SearchResult) {
        // For an already-running app, activate it directly so macOS switches
        // to its Space. NSWorkspace.open doesn't reliably trigger a Space
        // switch for running apps — NSRunningApplication.activate does.
        if result.fileExtension == "app",
           let bundleID = Bundle(url: result.url)?.bundleIdentifier,
           let runningApp = NSWorkspace.shared.runningApplications
               .first(where: { $0.bundleIdentifier == bundleID })
        {
            runningApp.activate(options: .activateIgnoringOtherApps)
        } else {
            NSWorkspace.shared.open(result.url)
        }
        dismiss()
    }

    // MARK: – Search
}
