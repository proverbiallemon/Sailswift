import SwiftUI

enum DetailViewMode: String, CaseIterable {
    case mods = "My Mods"
    case browse = "Browse"
}

/// Main application view
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedNode: ModTreeNode?
    @State private var showDeleteConfirmation = false
    @State private var detailMode: DetailViewMode = .mods
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            ModListView(selectedNode: $selectedNode, searchText: $searchText)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            switch detailMode {
            case .mods:
                ModDetailView(selectedNode: selectedNode)
            case .browse:
                ModBrowserView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { Task { await appState.launchGame() } }) {
                    Label("Launch Game", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            ToolbarItemGroup(placement: .principal) {
                Picker("View", selection: $detailMode) {
                    ForEach(DetailViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            ToolbarItemGroup(placement: .secondaryAction) {
                Button(action: toggleSelected) {
                    Label("Toggle", systemImage: "power")
                }
                .disabled(selectedNode == nil)

                Button(action: { showDeleteConfirmation = true }) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedNode == nil)

                Divider()

                Button(action: { FileService.shared.openInFinder(appState.modsDirectory) }) {
                    Label("Open Mods Folder", systemImage: "folder")
                }

                Button(action: { Task { await appState.loadMods() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search mods")
        .navigationTitle("Sailswift")
        .navigationSubtitle(appState.statusMessage)
        .alert("Delete", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteSelected() }
        } message: {
            Text("Are you sure you want to delete this item?")
        }
        .sheet(isPresented: $appState.showAbout) {
            AboutView()
        }
        .alert("Download", isPresented: $appState.showDownloadAlert) {
            Button("OK") { }
        } message: {
            Text(appState.downloadAlertMessage)
        }
        .sheet(isPresented: $appState.showImportConfirmation) {
            ImportConfirmationView()
        }
    }

    private func toggleSelected() {
        guard let node = selectedNode else { return }
        Task {
            switch node {
            case .mod(let mod): await appState.toggleMod(mod)
            case .folder(let folder, _): await appState.toggleFolder(folder.path)
            }
        }
    }

    private func deleteSelected() {
        guard let node = selectedNode else { return }
        Task {
            switch node {
            case .mod(let mod): await appState.deleteMod(mod)
            case .folder(let folder, _): await appState.deleteFolder(folder.path)
            }
            selectedNode = nil
        }
    }
}

/// Detail view showing mod information
struct ModDetailView: View {
    let selectedNode: ModTreeNode?
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let node = selectedNode {
            switch node {
            case .mod(let mod):
                ModInfoSplitView(mod: mod)
            case .folder(let folder, let children):
                FolderContentsView(folder: folder, children: children)
            }
        } else {
            EmptyStateView(title: "No Selection", systemImage: "folder", description: "Select a mod or folder")
        }
    }
}

/// Shows mod details on the left and GameBanana search on the right
struct ModInfoSplitView: View {
    let mod: Mod
    @EnvironmentObject var appState: AppState
    @ObservedObject private var cache = GameBananaModCache.shared
    @State private var filterText: String = ""
    @State private var webViewURL: URL?
    @State private var hasInitializedFilter = false

    /// Get fresh mod data from AppState (in case it was toggled)
    private var currentMod: Mod {
        appState.mods.first { $0.name == mod.name && $0.folderPath == mod.folderPath } ?? mod
    }

    private var filteredMods: [GameBananaMod] {
        guard !filterText.isEmpty else { return Array(cache.mods.prefix(20)) }
        return cache.mods
            .compactMap { gbMod -> (mod: GameBananaMod, score: Int)? in
                if let nameScore = gbMod.name.fuzzyMatch(filterText) {
                    return (gbMod, nameScore)
                } else if let authorScore = gbMod.author.fuzzyMatch(filterText) {
                    return (gbMod, authorScore)
                }
                return nil
            }
            .sorted { $0.score > $1.score }
            .map { $0.mod }
    }

    var body: some View {
        if let url = webViewURL {
            GameBananaWebView(initialURL: url) {
                webViewURL = nil
            }
        } else {
            HSplitView {
                // Left side: Mod details
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: currentMod.isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(currentMod.isEnabled ? .green : .red)
                            .font(.system(size: 40))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentMod.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text(currentMod.isEnabled ? "Enabled" : "Disabled")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: { Task { await appState.toggleMod(currentMod) } }) {
                            Label(currentMod.isEnabled ? "Disable" : "Enable", systemImage: "power")
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    // Details
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("File") {
                            Text(currentMod.path.lastPathComponent)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        LabeledContent("Location") {
                            Text(currentMod.folderPath.isEmpty ? "Root" : currentMod.folderPath)
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("Extension") {
                            Text(".\(currentMod.fileExtension.rawValue)")
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // Actions
                    Button(action: { FileService.shared.revealInFinder(currentMod.path) }) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
                .padding()
                .frame(minWidth: 300, idealWidth: 350)

                // Right side: GameBanana results with filter
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "globe")
                        Text("GameBanana")
                            .font(.headline)
                        Spacer()
                        if cache.isLoading {
                            ProgressView().scaleEffect(0.7)
                            Text(cache.loadProgress).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(.bar)

                    // Filter bar
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Filter mods...", text: $filterText)
                            .textFieldStyle(.plain)
                        if !filterText.isEmpty {
                            Button(action: { filterText = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()

                    if cache.mods.isEmpty && cache.isLoading {
                        VStack {
                            ProgressView()
                            Text("Loading mods...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredMods.isEmpty {
                        EmptyStateView(title: "No Results", systemImage: "magnifyingglass", description: "No mods found matching \"\(filterText)\"")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredMods) { gbMod in
                                    GameBananaResultRow(mod: gbMod, onOpenInApp: { url in
                                        webViewURL = url
                                    })
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(minWidth: 300)
                .background(Color(.windowBackgroundColor))
            }
            .task {
                await cache.loadAllIfNeeded()
                // Pre-fill filter with mod name on first appearance
                if !hasInitializedFilter {
                    filterText = mod.name
                    hasInitializedFilter = true
                }
            }
            .onChange(of: mod.id) { _ in
                // Update filter when selecting a different mod
                filterText = mod.name
            }
        }
    }
}

/// Row showing a GameBanana search result
struct GameBananaResultRow: View {
    let mod: GameBananaMod
    var onOpenInApp: ((URL) -> Void)?
    @EnvironmentObject var appState: AppState
    @State private var isHovering = false
    @State private var showFiles = false
    @State private var files: [GameBananaFile] = []
    @State private var isLoadingFiles = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: mod.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
            }
            .frame(width: 80, height: 60)
            .cornerRadius(6)
            .clipped()

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(mod.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    Label(mod.author, systemImage: "person")
                    Spacer()
                    Label(mod.formattedLikeCount, systemImage: "heart")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button(action: { onOpenInApp?(mod.profileURL) }) {
                    Image(systemName: "globe")
                }
                .buttonStyle(.bordered)
                .help("View on GameBanana")

                Button(action: { showFiles = true }) {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .help("Download")
            }
        }
        .padding(10)
        .background(isHovering ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
        .cornerRadius(8)
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

/// Shows all mods in a folder as a grid
struct FolderContentsView: View {
    let folder: ModFolder
    let children: [ModTreeNode]
    @EnvironmentObject var appState: AppState

    /// Get fresh mods from AppState that belong to this folder
    private var folderMods: [Mod] {
        appState.mods.filter { mod in
            mod.folderPath == folder.relativePath || mod.folderPath.hasPrefix(folder.relativePath + "/")
        }.sorted { $0.name < $1.name }
    }

    /// Calculate current folder state from fresh data
    private var currentFolderState: ModFolderState {
        if folderMods.isEmpty { return .empty }
        let enabledCount = folderMods.filter { $0.isEnabled }.count
        if enabledCount == folderMods.count { return .allEnabled }
        if enabledCount == 0 { return .allDisabled }
        return .mixed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: currentFolderState.iconName)
                    .foregroundColor(colorForState(currentFolderState))
                    .font(.system(size: 32))

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("\(folderMods.count) mods • \(folderMods.filter { $0.isEnabled }.count) enabled")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { Task { await appState.toggleFolder(folder.path) } }) {
                    Label("Toggle All", systemImage: "power")
                }
                .buttonStyle(.bordered)

                Button(action: { FileService.shared.openInFinder(folder.path) }) {
                    Label("Open in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.bar)

            Divider()

            // Mod grid
            if folderMods.isEmpty {
                EmptyStateView(title: "Empty Folder", systemImage: "folder", description: "No mods in this folder")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 12)], spacing: 12) {
                        ForEach(folderMods, id: \.id) { mod in
                            FolderModCard(mod: mod)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func colorForState(_ state: ModFolderState) -> Color {
        switch state {
        case .allEnabled: return .green
        case .allDisabled: return .red
        case .mixed: return .orange
        case .empty: return .gray
        }
    }
}

/// Card showing a mod within a folder
struct FolderModCard: View {
    let mod: Mod
    @EnvironmentObject var appState: AppState
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mod.isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(mod.isEnabled ? .green : .red)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(".\(mod.fileExtension.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { Task { await appState.toggleMod(mod) } }) {
                Image(systemName: "power")
            }
            .buttonStyle(.bordered)
            .help(mod.isEnabled ? "Disable" : "Enable")
        }
        .padding(12)
        .background(isHovering ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
        .cornerRadius(8)
        .onHover { isHovering = $0 }
    }
}

/// Custom empty state view for macOS 13 compatibility
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Confirmation sheet for importing mods from URL scheme
struct ImportConfirmationView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("Install Mod")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(.bar)

            Divider()

            if let pending = appState.pendingImport {
                if pending.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Fetching mod information...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = pending.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("Error")
                            .font(.headline)
                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if let file = pending.file {
                    // Mod and file details
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Mod info header (if available)
                            if let mod = pending.mod {
                                HStack(alignment: .top, spacing: 16) {
                                    // Thumbnail
                                    AsyncImage(url: mod.imageURL) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        default:
                                            Rectangle().fill(Color.gray.opacity(0.2))
                                        }
                                    }
                                    .frame(width: 120, height: 90)
                                    .cornerRadius(8)
                                    .clipped()

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(mod.name)
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Label(mod.author, systemImage: "person")
                                            .foregroundColor(.secondary)
                                        Label(mod.category, systemImage: "folder")
                                            .foregroundColor(.secondary)
                                        HStack(spacing: 16) {
                                            Label(mod.formattedLikeCount, systemImage: "heart")
                                            Label(mod.formattedViewCount, systemImage: "eye")
                                        }
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    }
                                }
                            } else {
                                // Fallback header when mod info not available
                                HStack(alignment: .top, spacing: 16) {
                                    Image(systemName: "doc.zipper")
                                        .font(.system(size: 48))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 80, height: 80)
                                        .background(Color(.controlBackgroundColor))
                                        .cornerRadius(12)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text((file.filename as NSString).deletingPathExtension)
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Text("From GameBanana")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Divider()

                            // File details
                            VStack(alignment: .leading, spacing: 8) {
                                Text("File to Download")
                                    .font(.headline)
                                HStack {
                                    Image(systemName: "doc.zipper")
                                        .foregroundColor(.secondary)
                                    Text(file.filename)
                                    Spacer()
                                    Text(file.formattedFilesize)
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .background(Color(.controlBackgroundColor))
                                .cornerRadius(8)

                                HStack(spacing: 16) {
                                    if file.downloadCount > 0 {
                                        Label("\(file.downloadCount) downloads", systemImage: "arrow.down.circle")
                                    }
                                    if !file.analysisResult.isEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: file.analysisResult == "ok" ? "checkmark.shield.fill" : "exclamationmark.shield")
                                                .foregroundColor(file.analysisResult == "ok" ? .green : .orange)
                                            Text(file.analysisResult == "ok" ? "Clean" : file.analysisResult)
                                        }
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            Divider()

                            // Install location
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Install Location")
                                    .font(.headline)
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundColor(.secondary)
                                    Text(PathConstants.modsDirectory.path)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    EmptyStateView(title: "No File Info", systemImage: "questionmark.circle", description: "Could not retrieve file information")
                }
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    appState.cancelImport()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if let pending = appState.pendingImport {
                    Button(action: {
                        if let url = URL(string: "https://gamebanana.com/mods/\(pending.modId)") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Label("View on GameBanana", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                }

                Button("Install") {
                    Task { await appState.confirmImport() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(appState.pendingImport?.file == nil)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
    }
}
