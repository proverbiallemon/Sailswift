import SwiftUI

/// Settings/Preferences view
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView().tabItem { Label("General", systemImage: "gear") }
            BehaviorSettingsView().tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 450, height: 280)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showGamePicker = false

    var body: some View {
        Form {
            Section("Paths") {
                LabeledContent("Game Location") {
                    HStack {
                        Text(appState.gamePath.isEmpty ? "Not Set" : appState.gamePath)
                            .foregroundColor(appState.gamePath.isEmpty ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Button("Browse...") { showGamePicker = true }
                    }
                }

                LabeledContent("Mods Folder") {
                    Text(PathConstants.modsDirectory.path).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }

            Section("Quick Actions") {
                Button("Open Mods Folder") { FileService.shared.openInFinder(PathConstants.modsDirectory) }
                Button("Open Game Config Folder") { FileService.shared.openInFinder(PathConstants.sohAppSupportDirectory) }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showGamePicker, allowedContentTypes: [.application], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                if PathConstants.validateGameInstallation(at: url) { appState.gamePath = url.path }
            }
        }
    }
}

struct BehaviorSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { !appState.skipUpdateCheck },
                    set: { newValue in
                        appState.skipUpdateCheck = !newValue
                        UpdaterService.shared.automaticallyChecksForUpdates = newValue
                    }
                ))

                Button("Check for Updates Now...") {
                    UpdaterService.shared.checkForUpdates()
                }
            }

            Section("Mods") {
                Toggle("Auto-enable AltAssets when mods are active", isOn: $appState.enableAltAssets)
                Toggle("Confirm before deleting mods", isOn: $appState.confirmDelete)
            }
        }
        .formStyle(.grouped)
    }
}
