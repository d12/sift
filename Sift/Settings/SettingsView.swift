import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)

            IndexingSettingsView()
                .tabItem { Label("Indexing", systemImage: "folder.badge.gearshape") }
                .tag(1)
        }
        .frame(width: 580, height: 560)
    }
}
