import SwiftUI

/// About window view
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            VStack(spacing: 4) {
                Text("Sailswift").font(.largeTitle).fontWeight(.bold)
                Text("Version \(appVersion) (\(buildNumber))").font(.subheadline).foregroundColor(.secondary)
            }

            Text("Native macOS mod manager for Ship of Harkinian")
                .font(.body).multilineTextAlignment(.center).foregroundColor(.secondary)

            Divider().padding(.horizontal, 40)

            VStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/proverbiallemon/Sailswift")!) {
                    Label("View on GitHub", systemImage: "link")
                }
                Link(destination: URL(string: "https://www.shipofharkinian.com")!) {
                    Label("Ship of Harkinian", systemImage: "gamecontroller")
                }
                Link(destination: URL(string: "https://gamebanana.com/games/16121")!) {
                    Label("GameBanana Mods", systemImage: "arrow.down.circle")
                }
            }

            Divider().padding(.horizontal, 40)

            VStack(spacing: 4) {
                Text("A rewrite of Saildeck optimized for Mac").font(.caption).foregroundColor(.secondary)
                Text("Built with SwiftUI").font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(width: 400, height: 500)
    }
}
