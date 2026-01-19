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

    /// Whether there are any active or pending downloads
    private var hasActiveDownloads: Bool {
        !appState.downloadManager.downloads.isEmpty || appState.pendingImport != nil
    }

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
                // Downloads button - anchor for popover, toggles visibility
                Button(action: { appState.toggleDownloadPopover() }) {
                    Label("Downloads", systemImage: downloadButtonIcon)
                }
                .popover(isPresented: $appState.showDownloadPopover, arrowEdge: .bottom) {
                    ImportPopoverView(downloadManager: appState.downloadManager)
                        .environmentObject(appState)
                }
                .opacity(hasActiveDownloads ? 1 : 0.5)

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
        .alert("7-Zip Required", isPresented: $appState.show7zMissingAlert) {
            Button("Install via Homebrew") {
                appState.install7zipViaHomebrew()
            }
            Button("Copy Command") {
                appState.copy7zipCommand()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This mod is packaged as a .7z archive which requires 7-Zip to extract.\n\nInstall it with Homebrew or copy the command to run manually.")
        }
    }

    /// Icon for the downloads button based on current state
    private var downloadButtonIcon: String {
        let downloads = appState.downloadManager.downloads
        // Check if any download is in progress
        if downloads.contains(where: { $0.status == .downloading }) {
            return "arrow.down.circle.fill"
        }
        if downloads.contains(where: { $0.status == .extracting }) {
            return "archivebox.fill"
        }
        if downloads.contains(where: { $0.status == .failed }) {
            return "xmark.circle.fill"
        }
        if !downloads.isEmpty || appState.pendingImport != nil {
            return "arrow.down.circle.fill"
        }
        return "arrow.down.circle"
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

    /// Name to use for GameBanana search - checks metadata, then folder name, then file name
    private var searchableName: String {
        mod.searchableName(modsDirectory: appState.modsDirectory)
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
                // Pre-fill filter with searchable name on first appearance
                if !hasInitializedFilter {
                    filterText = searchableName
                    hasInitializedFilter = true
                }
            }
            .onChange(of: mod.id) { _ in
                // Update filter when selecting a different mod
                filterText = searchableName
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

                Button(action: { Task { await appState.handleBrowseImport(mod: mod) } }) {
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

/// Popover for importing mods - click outside to dismiss
struct ImportPopoverView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var downloadManager: DownloadManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Downloads")
                    .font(.headline)
                Spacer()
                if !downloadManager.downloads.isEmpty {
                    Button(action: { appState.closeDownloadPopover() }) {
                        Text("Clear All")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(.bar)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Show pending import first
                    if let pending = appState.pendingImport {
                        importConfirmationView(pending: pending)
                        if !downloadManager.downloads.isEmpty {
                            Divider()
                        }
                    }

                    // Show all downloads
                    ForEach(downloadManager.downloads) { download in
                        DownloadProgressRow(download: download, onClear: {
                            appState.clearDownload(download)
                        })
                    }

                    // Empty state
                    if downloadManager.downloads.isEmpty && appState.pendingImport == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle")
                                .font(.title)
                                .foregroundColor(.secondary)
                            Text("No downloads")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 400)
    }

    // MARK: - Import Confirmation View

    @ViewBuilder
    private func importConfirmationView(pending: PendingImport) -> some View {
        VStack(spacing: 0) {
            if pending.isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Fetching mod info...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            } else if let error = pending.error {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        appState.cancelImport()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            } else if let file = pending.file {
                VStack(spacing: 0) {
                    // Mod info header
                    HStack(alignment: .top, spacing: 12) {
                        if let mod = pending.mod {
                            AsyncImage(url: mod.imageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Rectangle().fill(Color.gray.opacity(0.2))
                                }
                            }
                            .frame(width: 60, height: 45)
                            .cornerRadius(4)
                            .clipped()

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mod.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(mod.author)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Image(systemName: "doc.zipper")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                            Text((file.filename as NSString).deletingPathExtension)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        Spacer()
                    }

                    // File selection (if multiple files)
                    if pending.files.count > 1 {
                        Divider().padding(.vertical, 8)
                        VStack(spacing: 6) {
                            ForEach(pending.files) { f in
                                CompactFileRow(
                                    file: f,
                                    isSelected: f.fileId == file.fileId,
                                    onSelect: { appState.selectImportFile(f) }
                                )
                            }
                        }
                    }

                    Divider().padding(.vertical, 8)

                    // Selected file info + Install button
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.filename)
                                .font(.caption)
                                .lineLimit(1)
                            Text(file.formattedFilesize)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            Task { await appState.confirmImport() }
                        }) {
                            Label("Install", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }
}

/// Row showing download progress
struct DownloadProgressRow: View {
    let download: Download
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Header with name and status icon
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text(download.modName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                if download.status == .completed || download.status == .failed {
                    Button(action: onClear) {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            // Progress bar (only show if downloading or extracting)
            if download.status == .downloading || download.status == .extracting {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: download.progress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text(download.progressText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(download.progress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Status message for completed/failed
            if download.status == .completed || download.status == .failed {
                HStack {
                    Text(download.statusMessage)
                        .font(.caption)
                        .foregroundColor(download.status == .completed ? .green : .red)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var statusIcon: String {
        switch download.status {
        case .pending: return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .extracting: return "archivebox.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch download.status {
        case .pending: return .secondary
        case .downloading: return .blue
        case .extracting: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}

/// Compact file selection row for popover
struct CompactFileRow: View {
    let file: GameBananaFile
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename)
                        .font(.caption)
                        .lineLimit(1)
                    Text(file.formattedFilesize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !file.analysisResult.isEmpty {
                    Image(systemName: file.analysisResult == "ok" ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .foregroundColor(file.analysisResult == "ok" ? .green : .orange)
                        .font(.caption)
                }
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

/// Row for selecting a file in the import confirmation
struct FileSelectionRow: View {
    let file: GameBananaFile
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)

                Image(systemName: "doc.zipper")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(file.formattedFilesize)
                        Text("•")
                        Text("\(file.downloadCount) downloads")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if !file.analysisResult.isEmpty {
                    Image(systemName: file.analysisResult == "ok" ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .foregroundColor(file.analysisResult == "ok" ? .green : .orange)
                }
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
