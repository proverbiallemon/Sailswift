import SwiftUI

/// Card view for displaying a mod from GameBanana
struct ModCardView: View {
    let mod: GameBananaMod
    var onOpenInApp: ((URL) -> Void)?

    @EnvironmentObject var appState: AppState
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: mod.imageURL) { phase in
                switch phase {
                case .empty: Rectangle().fill(Color.gray.opacity(0.2)).overlay { ProgressView() }
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                case .failure: Rectangle().fill(Color.gray.opacity(0.2)).overlay { Image(systemName: "photo").foregroundColor(.secondary) }
                @unknown default: Rectangle().fill(Color.gray.opacity(0.2))
                }
            }
            .frame(height: 150)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(mod.name).font(.headline).lineLimit(2).frame(height: 44, alignment: .topLeading)

                HStack {
                    Label(mod.author, systemImage: "person")
                    Spacer()
                    Text(mod.category).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1)).cornerRadius(4)
                }
                .font(.caption).foregroundColor(.secondary)

                HStack(spacing: 16) {
                    Label(mod.formattedViewCount, systemImage: "eye")
                    Label(mod.formattedLikeCount, systemImage: "heart")
                    Spacer()
                    if let date = mod.dateAdded { Text(date.relativeString) }
                }
                .font(.caption).foregroundColor(.secondary)

                Divider()

                HStack(spacing: 8) {
                    Button(action: { Task { await appState.handleBrowseImport(mod: mod) } }) {
                        Label("Download", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: {
                        if let onOpenInApp = onOpenInApp {
                            onOpenInApp(mod.profileURL)
                        } else {
                            NSWorkspace.shared.open(mod.profileURL)
                        }
                    }) {
                        Image(systemName: "globe")
                    }
                    .buttonStyle(.bordered)
                    .help("View on GameBanana")
                }
            }
            .padding(12)
        }
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture { Task { await appState.handleBrowseImport(mod: mod) } }
        .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 8 : 4)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
