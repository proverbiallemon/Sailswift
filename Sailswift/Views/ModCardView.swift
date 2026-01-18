import SwiftUI

/// Card view for displaying a mod from GameBanana
struct ModCardView: View {
    let mod: GameBananaMod
    var onOpenInApp: ((URL) -> Void)?

    @EnvironmentObject var appState: AppState
    @State private var isHovering = false
    @State private var showFiles = false
    @State private var files: [GameBananaFile] = []
    @State private var isLoadingFiles = false

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
                    Button(action: { showFiles = true }) {
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
        .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 8 : 4)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { isHovering = $0 }
        .sheet(isPresented: $showFiles) {
            FileSelectionSheet(mod: mod, files: files, isLoading: isLoadingFiles, onAppear: loadFiles) { file in
                showFiles = false
                Task { await appState.downloadManager.downloadFile(file, modName: mod.name) }
            }
        }
    }

    private func loadFiles() {
        guard files.isEmpty else { return }
        isLoadingFiles = true
        Task {
            do { files = try await GameBananaAPI.shared.fetchModFiles(modId: mod.modId) }
            catch { print("Error loading files: \(error)") }
            isLoadingFiles = false
        }
    }
}

struct FileSelectionSheet: View {
    let mod: GameBananaMod
    let files: [GameBananaFile]
    let isLoading: Bool
    let onAppear: () -> Void
    let onDownload: (GameBananaFile) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Download \(mod.name)").font(.headline)
                    Text("Select a file").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if isLoading {
                VStack { ProgressView(); Text("Loading...").foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                EmptyStateView(title: "No Files", systemImage: "doc.questionmark", description: "No downloadable files")
            } else {
                List(files) { file in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.zipper").font(.title2).foregroundColor(.accentColor).frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.filename).font(.headline).lineLimit(1)
                            HStack(spacing: 12) {
                                Text(file.formattedFilesize)
                                Text("\(file.downloadCount) downloads")
                            }
                            .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: { onDownload(file) }) {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 500, height: 400)
        .onAppear(perform: onAppear)
    }
}
