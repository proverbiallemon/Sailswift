import SwiftUI
import AppKit

@main
struct SailswiftApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Use Window instead of WindowGroup for single-window behavior
        Window("Sailswift", id: "main") {
            MainView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Sailswift") {
                    appState.showAbout = true
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdaterService.shared.checkForUpdates()
                }
            }
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    /// Handle incoming URLs from the shipofharkinian:// scheme
    /// Format: shipofharkinian://https//gamebanana.com/mmdl/{mod_id},Mod,{file_id}
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "shipofharkinian" else { return }

        // Bring app to front
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Parse the URL - format is shipofharkinian://https//gamebanana.com/mmdl/1593301,Mod,640119
        let urlString = url.absoluteString

        // Remove the scheme prefix
        let withoutScheme = urlString.replacingOccurrences(of: "shipofharkinian://", with: "")

        // Fix the URL format (https// -> https://)
        let fixedURL = withoutScheme.replacingOccurrences(of: "https//", with: "https://")

        // Parse the mmdl URL
        // Format: https://gamebanana.com/mmdl/{file_id},Mod,{mod_id}
        if fixedURL.contains("gamebanana.com/mmdl/") {
            let components = fixedURL.components(separatedBy: "/mmdl/")
            if components.count == 2 {
                let params = components[1].components(separatedBy: ",")
                if params.count >= 3 {
                    let fileId = params[0]
                    let itemType = params[1]
                    let modId = params[2]

                    print("[URL Handler] Received mod download request:")
                    print("  File ID: \(fileId)")
                    print("  Type: \(itemType)")
                    print("  Mod ID: \(modId)")

                    // Show import confirmation instead of downloading immediately
                    Task {
                        await appState.handleImportRequest(
                            modId: modId,
                            itemType: itemType,
                            fileId: fileId
                        )
                    }
                }
            }
        }
    }
}

/// App delegate to handle single-window behavior
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable automatic window tabbing (removes "Show Tab Bar" menu item)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Ensure we're the frontmost app when launched via URL
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Reopen main window if closed
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
}
