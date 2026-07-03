import SwiftUI
import KeyboardShortcuts
import ServiceManagement

struct GeneralSettingsView: View {

    @State private var showSpotlightGuide = false
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Sift", name: .toggleSift)
                    .onChange(of: KeyboardShortcuts.getShortcut(for: .toggleSift)) { _, shortcut in
                        showSpotlightGuide = isSystemConflict(shortcut)
                    }

                if showSpotlightGuide || isSystemConflict(KeyboardShortcuts.getShortcut(for: .toggleSift)) {
                    spotlightGuide
                }
            } header: {
                Text("Global Shortcut")
            } footer: {
                Text("This shortcut works system-wide, even when Sift is not the active app.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Revert the toggle if registration fails (e.g. unsigned debug build)
                            launchAtLogin = !enabled
                            print("[Sift] Login item \(enabled ? "register" : "unregister") failed: \(error)")
                        }
                    }
            } header: {
                Text("Startup")
            }

            Section {
                disableSpotlightSection
            } header: {
                Text("Spotlight")
            } footer: {
                Text("Disabling Spotlight reduces background CPU and disk usage and removes duplicate results from other search tools.")
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                Link("View on GitHub", destination: URL(string: "https://github.com/sift-app/sift")!)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: – Disable Spotlight section

    private var disableSpotlightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("If you use Sift as your primary search tool you can turn off Spotlight to save system resources. Open Terminal and run these commands:")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            commandRow(label: "Disable Spotlight indexing", command: "sudo mdutil -i off -a")
            commandRow(label: "Re-enable Spotlight indexing", command: "sudo mdutil -i on -a")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func commandRow(label: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
        }
    }

    // MARK: – System conflict guide

    @ViewBuilder
    private var spotlightGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This shortcut is reserved by macOS", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline.weight(.medium))

            Text("⌘Space is Spotlight and ⌘⌥Space opens Finder search — both are system shortcuts. To use one of them for Sift, disable it first:")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(spotlightSteps, id: \.self) { step in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(step).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            Button("Open Keyboard Settings…") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
                )
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.orange.opacity(0.25), lineWidth: 1)
        )
    }

    private let spotlightSteps = [
        "Open System Settings → Keyboard → Keyboard Shortcuts…",
        "Select \"Spotlight\" in the left sidebar.",
        "Uncheck \"Show Spotlight search\".",
        "Close System Settings — your new shortcut takes effect immediately.",
    ]

    // MARK: – Helpers

    private func isSystemConflict(_ shortcut: KeyboardShortcuts.Shortcut?) -> Bool {
        guard let s = shortcut, s.key == .space else { return false }
        return s.modifiers == .command || s.modifiers == [.command, .option]
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}
