 import SwiftUI
import Combine

/// A notification message for the ticker
struct NotificationMessage: Identifiable {
    let id = UUID()
    let text: String
    let type: NotificationType
    let timestamp: Date

    init(_ text: String, type: NotificationType = .info) {
        self.text = text
        self.type = type
        self.timestamp = Date()
    }

    enum NotificationType {
        case info
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .info: return .secondary
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
}

/// Tracks a mod download initiated by profile application
struct ProfileDownloadProgress: Identifiable {
    let id = UUID()
    let modName: String
    let folderName: String
    var fileId: Int = 0  // Used to correlate with DownloadManager
    var progress: Double = 0
    var status: ProfileDownloadStatus = .downloading
    var bytesDownloaded: Int64 = 0
    var totalBytes: Int64 = 0
    var isDismissing: Bool = false  // Triggers swipe-out animation

    var progressText: String {
        switch status {
        case .downloading:
            if totalBytes > 0 {
                let downloaded = ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                return "\(downloaded) / \(total)"
            }
            return "Downloading..."
        case .extracting:
            return "Extracting..."
        case .completed:
            return "Complete"
        case .failed:
            return "Failed"
        }
    }
}

enum ProfileDownloadStatus {
    case downloading
    case extracting
    case completed
    case failed
}

/// Tracks a pending batch deletion for confirmation
struct PendingDeletion: Identifiable {
    let id = UUID()
    let folderPaths: [String]  // Relative paths of folders to delete
    let modCount: Int          // Total number of mods in these folders

    var confirmationText: String {
        if folderPaths.count == 1 {
            return "Delete \(folderPaths.first ?? "folder")?"
        } else {
            return "Delete \(folderPaths.count) folders (\(modCount) mods)?"
        }
    }

    var tickerText: String {
        if folderPaths.count == 1 {
            return "Delete \(folderPaths.first ?? "folder")? Click to confirm."
        } else {
            return "Delete \(folderPaths.count) folders (\(modCount) mods)? Click to confirm."
        }
    }
}

/// Represents a pending mod import from URL scheme or browse view
struct PendingImport: Identifiable {
    let id = UUID()
    let modId: String
    let itemType: String
    var selectedFileId: String
    var mod: GameBananaMod?
    var files: [GameBananaFile] = []
    var isLoading = true
    var error: String?

    /// The currently selected file
    var file: GameBananaFile? {
        files.first { String($0.fileId) == selectedFileId } ?? files.first
    }
}

/// Global application state
@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties

    @Published var mods: [Mod] = []
    @Published var isLoading = false
    @Published var statusMessage = "Ready"
    @Published var showAbout = false
    @Published var selectedMod: Mod?
    @Published var expandedFolders: Set<String> = []
    @Published var showDownloadAlert = false
    @Published var downloadAlertMessage = ""
    @Published var show7zMissingAlert = false
    @Published var showUnrarMissingAlert = false

    // Import confirmation and download popover
    @Published var pendingImport: PendingImport?
    @Published var showImportConfirmation = false
    @Published var showDownloadPopover = false

    // Mod load order (mod names in priority order - later = higher priority)
    @Published var modLoadOrder: [String] = []

    // Profile downloads in progress (shown as placeholders in mod list)
    @Published var profileDownloads: [ProfileDownloadProgress] = []
    private var profileDownloadsScheduledForRemoval: Set<UUID> = []

    // Notification ticker
    @Published var notifications: [NotificationMessage] = []
    @Published var currentTickerMessage: NotificationMessage?
    @Published var showNotificationPopover = false

    // Confirmation ticker (for destructive actions)
    @Published var pendingDeletion: PendingDeletion?
    @Published var showDeleteConfirmPopover = false

    // Multi-selection
    @Published var selectedFolders: Set<String> = []  // Folder paths selected for batch operations
    @Published var multiSelectModeEnabled: Bool = false  // User-toggled multi-select mode

    /// True when in multi-select mode (either user-toggled or has selections from Cmd+click)
    var isInMultiSelectMode: Bool {
        multiSelectModeEnabled || !selectedFolders.isEmpty
    }

    // Modpack to profile conversion
    @Published var pendingModpackProfile: Modpack?  // Modpack awaiting profile creation
    @Published var showModpackProfilePopover = false

    // MARK: - Settings

    @AppStorage("gamePath") var gamePath: String = ""
    @AppStorage("skipUpdateCheck") var skipUpdateCheck = false
    @AppStorage("enableAltAssets") var enableAltAssets = true
    @AppStorage("confirmDelete") var confirmDelete = true

    // MARK: - Managers

    let modManager = ModManager()
    let downloadManager = DownloadManager()
    let gameConfigService = GameConfigService()
    let updaterService = UpdaterService.shared
    let modUpdateChecker = ModUpdateChecker.shared
    let profileManager = ModProfileManager.shared
    let modpackManager = ModpackManager.shared

    private var downloadCancellable: AnyCancellable?

    // MARK: - Computed Properties

    var modsDirectory: URL {
        PathConstants.modsDirectory
    }

    var hasValidGamePath: Bool {
        !gamePath.isEmpty && FileManager.default.fileExists(atPath: gamePath)
    }

    // MARK: - Initialization

    init() {
        // Auto-detect game path if not set
        if gamePath.isEmpty {
            if let detected = detectGamePath() {
                gamePath = detected.path
            }
        }

        // Ensure mods directory exists
        PathConstants.ensureDirectoriesExist()

        // Sync update check preference with Sparkle
        updaterService.automaticallyChecksForUpdates = !skipUpdateCheck

        // Load mod load order from config
        loadModLoadOrder()

        // Set up download completion callback - only profile downloads go to ticker
        downloadManager.onDownloadComplete = { [weak self] success, message, isProfileDownload in
            Task { @MainActor in
                // Only add to ticker for profile downloads (Browse downloads stay in popover)
                if isProfileDownload {
                    self?.addNotification(message, type: success ? .success : .error)
                }
                if success {
                    await self?.loadMods()
                }
            }
        }

        // Set up 7-Zip missing callback
        downloadManager.on7zMissing = { [weak self] in
            Task { @MainActor in
                self?.show7zMissingAlert = true
            }
        }

        // Set up unrar missing callback
        downloadManager.onUnrarMissing = { [weak self] in
            Task { @MainActor in
                self?.showUnrarMissingAlert = true
            }
        }

        // Observe download manager to sync profile download progress
        // Throttle to max 10 updates/second to prevent UI lag with many downloads
        downloadCancellable = downloadManager.$downloads
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] downloads in
                self?.syncProfileDownloadProgress(from: downloads)
            }

        // Load mods
        Task {
            await loadMods()
        }
    }

    private func loadModLoadOrder() {
        do {
            modLoadOrder = try gameConfigService.getModLoadOrder()
        } catch {
            print("Warning: Could not load mod order: \(error)")
            modLoadOrder = []
        }
    }

    // MARK: - Mod Operations

    func loadMods() async {
        isLoading = true
        statusMessage = "Loading mods..."

        do {
            mods = try await modManager.loadMods(from: modsDirectory, loadOrder: modLoadOrder)

            // Ensure all enabled mods are in the load order
            var loadOrderChanged = false
            for mod in mods where mod.isEnabled {
                if !modLoadOrder.contains(mod.name) {
                    modLoadOrder.append(mod.name)
                    loadOrderChanged = true
                }
            }

            // Also remove any mods from load order that no longer exist or are disabled
            let enabledModNames = Set(mods.filter { $0.isEnabled }.map { $0.name })
            let beforeCount = modLoadOrder.count
            modLoadOrder.removeAll { !enabledModNames.contains($0) }
            if modLoadOrder.count != beforeCount {
                loadOrderChanged = true
            }

            // Sync to config if we made changes
            if loadOrderChanged {
                syncLoadOrderToConfig()
            }

            statusMessage = "Loaded \(mods.count) mods"
        } catch {
            statusMessage = "Error loading mods: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func toggleMod(_ mod: Mod) async {
        do {
            try await modManager.toggleMod(mod)

            // Update load order
            if mod.isEnabled {
                // Mod was enabled, now disabling - remove from load order
                modLoadOrder.removeAll { $0 == mod.name }
            } else {
                // Mod was disabled, now enabling - add to end of load order
                if !modLoadOrder.contains(mod.name) {
                    modLoadOrder.append(mod.name)
                }
            }
            syncLoadOrderToConfig()

            await loadMods()
            statusMessage = mod.isEnabled ? "Disabled \(mod.name)" : "Enabled \(mod.name)"
        } catch {
            statusMessage = "Error toggling mod: \(error.localizedDescription)"
        }
    }

    func toggleFolder(_ folderPath: URL) async {
        do {
            // Get the relative path of the folder being toggled
            let folderRelativePath = folderPath.path.replacingOccurrences(
                of: modsDirectory.path + "/",
                with: ""
            )

            // Get mods in this folder (mods whose path starts with or equals the folder path)
            let modsInFolder = mods.filter { mod in
                mod.folderPath == folderRelativePath ||
                mod.folderPath.hasPrefix(folderRelativePath + "/")
            }
            let wereEnabled = modsInFolder.first?.isEnabled ?? false

            try await modManager.toggleModsInFolder(folderPath)

            // Update load order based on toggle direction
            if wereEnabled {
                // Mods were enabled, now disabled - remove from load order
                for mod in modsInFolder {
                    modLoadOrder.removeAll { $0 == mod.name }
                }
            } else {
                // Mods were disabled, now enabled - add to load order
                for mod in modsInFolder {
                    if !modLoadOrder.contains(mod.name) {
                        modLoadOrder.append(mod.name)
                    }
                }
            }
            syncLoadOrderToConfig()

            await loadMods()
            statusMessage = "Toggled mods in folder"
        } catch {
            statusMessage = "Error toggling folder: \(error.localizedDescription)"
        }
    }

    func deleteMod(_ mod: Mod) async {
        do {
            try await modManager.deleteMod(mod)
            // Remove from load order
            modLoadOrder.removeAll { $0 == mod.name }
            syncLoadOrderToConfig()
            await loadMods()
            statusMessage = "Deleted \(mod.name)"
        } catch {
            statusMessage = "Error deleting mod: \(error.localizedDescription)"
        }
    }

    // MARK: - Load Order Management

    /// Reorder mods via drag and drop
    func reorderMods(from source: IndexSet, to destination: Int) {
        modLoadOrder.move(fromOffsets: source, toOffset: destination)
        syncLoadOrderToConfig()
        Task {
            await loadMods()
        }
    }

    /// Move a mod up in the load order (higher priority)
    func moveModUp(_ modName: String) {
        guard let index = modLoadOrder.firstIndex(of: modName), index > 0 else { return }
        modLoadOrder.swapAt(index, index - 1)
        syncLoadOrderToConfig()
        Task {
            await loadMods()
        }
    }

    /// Move a mod down in the load order (lower priority)
    func moveModDown(_ modName: String) {
        guard let index = modLoadOrder.firstIndex(of: modName), index < modLoadOrder.count - 1 else { return }
        modLoadOrder.swapAt(index, index + 1)
        syncLoadOrderToConfig()
        Task {
            await loadMods()
        }
    }

    /// Persist the current load order to the game config
    func syncLoadOrderToConfig() {
        do {
            try gameConfigService.setModLoadOrder(modLoadOrder)
        } catch {
            print("Warning: Could not save mod order: \(error)")
        }
    }

    /// Get the load order index for a mod (nil if not in order)
    func loadOrderIndex(for modName: String) -> Int? {
        modLoadOrder.firstIndex(of: modName)
    }

    /// Move a folder's mods to a new position in the load order
    /// - Parameters:
    ///   - folderPath: Relative path of the folder
    ///   - targetModName: The mod name to insert before/after
    ///   - insertAfter: If true, insert after target; if false, insert before
    func moveFolderInLoadOrder(folderPath: String, toIndex targetIndex: Int) {
        // Find all mods in this folder that are in the load order
        let modsInFolder = mods.filter { mod in
            mod.folderPath == folderPath || mod.folderPath.hasPrefix(folderPath + "/")
        }.map { $0.name }

        let modsToMove = modLoadOrder.filter { modsInFolder.contains($0) }
        guard !modsToMove.isEmpty else { return }

        // Remove them from current positions
        modLoadOrder.removeAll { modsInFolder.contains($0) }

        // Calculate adjusted insert index
        let insertIndex = min(targetIndex, modLoadOrder.count)

        // Insert at new position
        modLoadOrder.insert(contentsOf: modsToMove, at: insertIndex)

        syncLoadOrderToConfig()
        Task {
            await loadMods()
        }
    }

    /// Get enabled mod names in a folder
    func enabledModsInFolder(_ folderPath: String) -> [String] {
        mods.filter { mod in
            mod.isEnabled && (mod.folderPath == folderPath || mod.folderPath.hasPrefix(folderPath + "/"))
        }.map { $0.name }
    }

    func deleteFolder(_ folderPath: URL) async {
        do {
            try FileManager.default.removeItem(at: folderPath)
            await loadMods()
            statusMessage = "Deleted folder"
        } catch {
            statusMessage = "Error deleting folder: \(error.localizedDescription)"
        }
    }

    // MARK: - Multi-Selection & Batch Delete

    /// Toggle folder selection (for Command+click multi-select)
    func toggleFolderSelection(_ folderPath: String) {
        if selectedFolders.contains(folderPath) {
            selectedFolders.remove(folderPath)
        } else {
            selectedFolders.insert(folderPath)
        }
    }

    /// Clear all folder selections
    func clearFolderSelection() {
        selectedFolders.removeAll()
    }

    /// Toggle multi-select mode on/off
    func toggleMultiSelectMode() {
        if multiSelectModeEnabled {
            // Turning off - clear selections
            multiSelectModeEnabled = false
            selectedFolders.removeAll()
        } else {
            // Turning on
            multiSelectModeEnabled = true
        }
    }

    /// Exit multi-select mode (called after operations like delete)
    func exitMultiSelectMode() {
        multiSelectModeEnabled = false
        selectedFolders.removeAll()
    }

    /// Check if a folder is selected
    func isFolderSelected(_ folderPath: String) -> Bool {
        selectedFolders.contains(folderPath)
    }

    /// Request deletion of selected folders (shows confirmation ticker)
    func requestDeleteSelectedFolders() {
        guard !selectedFolders.isEmpty else { return }

        // Count mods in selected folders
        let modCount = mods.filter { mod in
            selectedFolders.contains(where: { folderPath in
                mod.folderPath == folderPath || mod.folderPath.hasPrefix(folderPath + "/")
            })
        }.count

        pendingDeletion = PendingDeletion(
            folderPaths: Array(selectedFolders),
            modCount: modCount
        )
    }

    /// Request deletion of a single folder (shows confirmation ticker)
    func requestDeleteFolder(_ folderPath: String) {
        let modCount = mods.filter { mod in
            mod.folderPath == folderPath || mod.folderPath.hasPrefix(folderPath + "/")
        }.count

        // Add to selection and create pending deletion
        selectedFolders = [folderPath]
        pendingDeletion = PendingDeletion(
            folderPaths: [folderPath],
            modCount: modCount
        )
    }

    /// Confirm and execute the pending deletion
    func confirmPendingDeletion() async {
        guard let pending = pendingDeletion else { return }

        var deletedCount = 0
        for folderPath in pending.folderPaths {
            let folderURL = modsDirectory.appendingPathComponent(folderPath)
            do {
                try FileManager.default.removeItem(at: folderURL)
                deletedCount += 1

                // Remove from load order
                let modsInFolder = mods.filter { $0.folderPath == folderPath || $0.folderPath.hasPrefix(folderPath + "/") }
                for mod in modsInFolder {
                    modLoadOrder.removeAll { $0 == mod.name }
                }
            } catch {
                print("Error deleting folder \(folderPath): \(error)")
            }
        }

        syncLoadOrderToConfig()
        await loadMods()

        // Clear state and exit multi-select mode
        pendingDeletion = nil
        exitMultiSelectMode()
        showDeleteConfirmPopover = false

        // Notify via ticker
        let message = deletedCount == 1
            ? "Deleted \(pending.folderPaths.first ?? "folder")"
            : "Deleted \(deletedCount) folders"
        addNotification(message, type: .info)
    }

    /// Cancel the pending deletion
    func cancelPendingDeletion() {
        pendingDeletion = nil
        exitMultiSelectMode()
        showDeleteConfirmPopover = false
    }

    // MARK: - Game Operations

    func launchGame() async {
        guard hasValidGamePath else {
            statusMessage = "Please set the game path in settings"
            return
        }

        let gameURL = URL(fileURLWithPath: gamePath)

        // Enable AltAssets if needed
        if enableAltAssets {
            let hasEnabledMods = mods.contains { $0.isEnabled }
            if hasEnabledMods {
                do {
                    try gameConfigService.enableAltAssets()
                    statusMessage = "AltAssets enabled"
                } catch {
                    print("Warning: Could not enable AltAssets: \(error)")
                }
            }
        }

        // Launch the game
        do {
            try await launchApplication(at: gameURL)
            statusMessage = "Game launched"

            // Optionally quit after launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            statusMessage = "Error launching game: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Methods

    private func detectGamePath() -> URL? {
        let possiblePaths = [
            "/Applications/soh.app",
            "\(NSHomeDirectory())/Applications/soh.app",
            "/Applications/Ship of Harkinian.app",
            "\(NSHomeDirectory())/Applications/Ship of Harkinian.app"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    private func launchApplication(at url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    // MARK: - Import Handling

    /// Handle an incoming URL scheme import request
    /// URL format: mmdl/{file_id},Mod,{mod_id}
    func handleImportRequest(modId: String, itemType: String, fileId: String) async {
        // Create pending import and show confirmation
        pendingImport = PendingImport(modId: modId, itemType: itemType, selectedFileId: fileId)
        showImportConfirmation = true
        showDownloadPopover = true

        // Fetch mod details and all files in parallel
        do {
            async let modTask = GameBananaAPI.shared.fetchModDetails(modId: Int(modId) ?? 0, itemType: itemType)
            async let filesTask = GameBananaAPI.shared.fetchModFiles(modId: Int(modId) ?? 0, itemType: itemType)

            let (mod, files) = try await (modTask, filesTask)

            pendingImport?.mod = mod
            pendingImport?.files = files
            pendingImport?.isLoading = false

            if files.isEmpty {
                pendingImport?.error = "Could not fetch file information"
            }
        } catch {
            pendingImport?.isLoading = false
            pendingImport?.error = error.localizedDescription
        }
    }

    /// Handle import request from browse view (auto-select first file)
    func handleBrowseImport(mod: GameBananaMod) async {
        // Create pending import with first file selected by default
        // Use the mod's actual item type (Mod, Sound, Skin, etc.)
        pendingImport = PendingImport(modId: String(mod.modId), itemType: mod.itemType, selectedFileId: "")
        pendingImport?.mod = mod
        showImportConfirmation = true
        showDownloadPopover = true

        // Fetch all files for this mod using the correct item type
        do {
            let files = try await GameBananaAPI.shared.fetchModFiles(modId: mod.modId, itemType: mod.itemType)
            pendingImport?.files = files
            if let firstFile = files.first {
                pendingImport?.selectedFileId = String(firstFile.fileId)
            }
            pendingImport?.isLoading = false

            if files.isEmpty {
                pendingImport?.error = "No downloadable files available"
            }
        } catch {
            pendingImport?.isLoading = false
            pendingImport?.error = error.localizedDescription
        }
    }

    /// Update the selected file in pending import
    func selectImportFile(_ file: GameBananaFile) {
        pendingImport?.selectedFileId = String(file.fileId)
    }

    /// Confirm and start the pending import
    func confirmImport() async {
        guard let pending = pendingImport, let file = pending.file else {
            showImportConfirmation = false
            pendingImport = nil
            return
        }

        // Keep popover open to show progress - don't close showImportConfirmation
        let modName = pending.mod?.name ?? (file.filename as NSString).deletingPathExtension
        let modId = pending.mod?.modId

        // Clear pending import but keep popover open for progress display
        pendingImport = nil

        await downloadManager.downloadFile(file, modName: modName, modId: modId)
    }

    /// Cancel the pending import (but keep popover open if there are active Browse mode downloads)
    func cancelImport() {
        showImportConfirmation = false
        pendingImport = nil
        // Only close popover if there are no active Browse mode downloads
        let browseDownloads = downloadManager.downloads.filter { !$0.isProfileDownload }
        if browseDownloads.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
            showDownloadPopover = false
        }
    }

    /// Toggle the download popover visibility
    func toggleDownloadPopover() {
        showDownloadPopover.toggle()
    }

    /// Close the download popover and clear completed Browse mode downloads
    func closeDownloadPopover() {
        showDownloadPopover = false
        // Clear completed/failed Browse mode downloads when closing (not profile downloads)
        downloadManager.downloads.removeAll {
            !$0.isProfileDownload && ($0.status == .completed || $0.status == .failed)
        }
        downloadManager.currentDownload = nil
    }

    /// Clear a specific download from the list
    func clearDownload(_ download: Download) {
        downloadManager.downloads.removeAll { $0.id == download.id }
        if downloadManager.currentDownload?.id == download.id {
            downloadManager.currentDownload = nil
        }
    }

    // MARK: - 7-Zip Installation

    /// Copy the brew install 7zip command to clipboard
    func copy7zipCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install 7zip", forType: .string)
        statusMessage = "Command copied to clipboard"
    }

    /// Check if 7-Zip is available
    var is7zipInstalled: Bool {
        downloadManager.is7zAvailable()
    }

    // MARK: - unar Installation

    /// Copy the brew install unar command to clipboard
    func copyUnarCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install unar", forType: .string)
        statusMessage = "Command copied to clipboard"
    }

    /// Check if unar is available
    var isUnarInstalled: Bool {
        downloadManager.isUnarAvailable()
    }

    // MARK: - Mod Update Checking

    /// Check installed mods for available updates from GameBanana
    func checkForModUpdates() async {
        await modUpdateChecker.checkForUpdates(modsDirectory: modsDirectory)
    }

    /// Check if a mod folder has an update available
    func hasModUpdate(for folderPath: String) -> Bool {
        modUpdateChecker.hasUpdate(for: folderPath)
    }

    /// Get the number of mods with available updates
    var modUpdatesAvailable: Int {
        modUpdateChecker.updates.count
    }

    /// Update a mod folder to its latest version from GameBanana
    func updateMod(folderPath: String) async {
        guard let updateInfo = modUpdateChecker.updateInfo(for: folderPath) else { return }

        let fullPath = modsDirectory.appendingPathComponent(folderPath)

        do {
            let files = try await GameBananaAPI.shared.fetchModFiles(modId: updateInfo.gameBananaModId)
            guard let file = files.first else {
                addNotification("No files available for \(updateInfo.modName)", type: .error)
                return
            }

            await downloadManager.downloadFile(
                file,
                modName: updateInfo.modName,
                modId: updateInfo.gameBananaModId,
                targetFolder: fullPath
            )

            modUpdateChecker.clearUpdate(for: folderPath)
            addNotification("Updated \(updateInfo.modName)", type: .success)
            await loadMods()
        } catch {
            addNotification("Update failed: \(error.localizedDescription)", type: .error)
        }
    }

    // MARK: - Profile Management

    /// Save current mod state as a new profile
    func saveProfile(name: String) {
        profileManager.saveCurrentState(name: name, mods: mods, loadOrder: modLoadOrder, modsDirectory: modsDirectory)
        let message = "Profile '\(name)' saved"
        statusMessage = message
        addNotification(message, type: .success)
    }

    /// Apply a saved profile
    func applyProfile(_ profile: ModProfile) async {
        statusMessage = "Applying profile '\(profile.name)'..."

        var changesApplied = 0
        var modsDownloading = 0
        var modsNotFound = 0
        var modsDisabled = 0

        // Collect downloads to start (we'll start them after toggling existing mods)
        var downloadsToStart: [(file: GameBananaFile, modName: String, modId: Int, folderName: String)] = []
        // Track which GameBanana mod IDs we've already queued to prevent duplicate downloads
        var queuedModIds: Set<Int> = []

        // Determine which format the profile uses
        let useNewFormat = !profile.modInfos.isEmpty

        // First: Disable any mods that are NOT in the profile
        // This handles mods downloaded after the profile was created
        let profileStableIds: Set<String>
        if useNewFormat {
            profileStableIds = Set(profile.modInfos.keys)
        } else if let legacyStates = profile.modStates {
            profileStableIds = Set(legacyStates.keys)
        } else {
            profileStableIds = []
        }

        for mod in mods where mod.isEnabled {
            if !profileStableIds.contains(mod.stableId) {
                // This enabled mod is not in the profile - disable it
                do {
                    try await modManager.toggleMod(mod)
                    modsDisabled += 1
                } catch {
                    print("Error disabling mod \(mod.name): \(error)")
                }
            }
        }

        if useNewFormat {
            // New format with modInfos
            for (stableId, info) in profile.modInfos {
                // Find mod by stableId
                if let mod = mods.first(where: { $0.stableId == stableId }) {
                    // Mod exists - toggle if needed
                    if mod.isEnabled != info.isEnabled {
                        do {
                            try await modManager.toggleMod(mod)
                            changesApplied += 1
                        } catch {
                            print("Error toggling mod \(mod.name): \(error)")
                        }
                    }
                } else if let modId = info.gameBananaModId {
                    // Mod is missing but has GameBanana ID - fetch files first
                    // Only download each mod ID once (multiple mods in same folder share the ID)
                    if !queuedModIds.contains(modId) {
                        queuedModIds.insert(modId)
                        do {
                            let files = try await GameBananaAPI.shared.fetchModFiles(modId: modId)
                            if let file = files.first {
                                let modName = info.gameBananaName ?? info.folderName
                                downloadsToStart.append((file, modName, modId, info.folderName))
                                modsDownloading += 1
                            } else {
                                modsNotFound += 1
                            }
                        } catch {
                            print("Error fetching mod files for \(info.folderName): \(error)")
                            modsNotFound += 1
                        }
                    }
                } else {
                    // Mod is missing and can't be downloaded
                    modsNotFound += 1
                }
            }
        } else if let legacyStates = profile.modStates {
            // Legacy format with modStates
            for (savedId, shouldBeEnabled) in legacyStates {
                var mod = mods.first(where: { $0.stableId == savedId })

                // Backwards compatibility: try stripping extensions
                if mod == nil {
                    let extensions = ["otr", "o2r", "disabled", "di2abled"]
                    for ext in extensions {
                        if savedId.hasSuffix(".\(ext)") {
                            let withoutExt = String(savedId.dropLast(ext.count + 1))
                            mod = mods.first(where: { $0.stableId == withoutExt })
                            if mod != nil { break }
                        }
                    }
                }

                guard let mod = mod else {
                    modsNotFound += 1
                    continue
                }

                if mod.isEnabled != shouldBeEnabled {
                    do {
                        try await modManager.toggleMod(mod)
                        changesApplied += 1
                    } catch {
                        print("Error toggling mod \(mod.name): \(error)")
                    }
                }
            }
        }

        // Apply load order
        modLoadOrder = profile.loadOrder
        syncLoadOrderToConfig()

        // Set as active profile
        profileManager.activeProfileId = profile.id

        // Reload mods to reflect changes
        await loadMods()

        // Create profile download entries and start downloads with staggered timing
        for (index, download) in downloadsToStart.enumerated() {
            var progressEntry = ProfileDownloadProgress(
                modName: download.modName,
                folderName: download.folderName
            )
            progressEntry.fileId = download.file.fileId
            profileDownloads.append(progressEntry)

            // Stagger download starts by 200ms each to prevent network/UI overload
            let delay = Double(index) * 0.2
            Task {
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                await downloadManager.downloadFile(download.file, modName: download.modName, modId: download.modId, isProfileDownload: true)
            }
        }

        // Build status message and notification
        var statusParts: [String] = []
        if modsDisabled > 0 {
            statusParts.append("\(modsDisabled) disabled")
        }
        if changesApplied > 0 {
            statusParts.append("\(changesApplied) toggled")
        }
        if modsDownloading > 0 {
            statusParts.append("\(modsDownloading) downloading")
        }
        if modsNotFound > 0 {
            statusParts.append("\(modsNotFound) not found")
        }

        let message: String
        let notificationType: NotificationMessage.NotificationType

        if statusParts.isEmpty {
            message = "Applied '\(profile.name)' (no changes needed)"
            notificationType = .info
        } else {
            message = "Applied '\(profile.name)': \(statusParts.joined(separator: ", "))"
            notificationType = modsNotFound > 0 ? .warning : .success
        }

        statusMessage = message
        addNotification(message, type: notificationType)
    }

    /// Update an existing profile with current state
    func updateProfile(_ profile: ModProfile) {
        profileManager.updateProfile(id: profile.id, mods: mods, loadOrder: modLoadOrder, modsDirectory: modsDirectory)
        let message = "Profile '\(profile.name)' updated"
        statusMessage = message
        addNotification(message, type: .success)
    }

    /// Delete a profile
    func deleteProfile(_ profile: ModProfile) {
        profileManager.deleteProfile(id: profile.id)
        let message = "Profile '\(profile.name)' deleted"
        statusMessage = message
        addNotification(message, type: .info)
    }

    // MARK: - Notification Ticker

    /// Add a notification to the ticker
    func addNotification(_ text: String, type: NotificationMessage.NotificationType = .info) {
        let notification = NotificationMessage(text, type: type)
        notifications.insert(notification, at: 0)

        // Keep only last 50 notifications
        if notifications.count > 50 {
            notifications = Array(notifications.prefix(50))
        }

        // Set as current ticker message
        currentTickerMessage = notification
    }

    /// Clear a specific notification
    func clearNotification(_ notification: NotificationMessage) {
        notifications.removeAll { $0.id == notification.id }
    }

    /// Clear all notifications
    func clearAllNotifications() {
        notifications.removeAll()
        currentTickerMessage = nil
    }

    /// Sync profile download progress from DownloadManager
    private func syncProfileDownloadProgress(from downloads: [Download]) {
        for i in profileDownloads.indices {
            let fileId = profileDownloads[i].fileId
            guard fileId > 0, let download = downloads.first(where: { $0.fileId == fileId }) else {
                continue
            }

            profileDownloads[i].progress = download.progress
            profileDownloads[i].bytesDownloaded = download.downloadedBytes
            profileDownloads[i].totalBytes = download.totalBytes

            switch download.status {
            case .pending, .downloading:
                profileDownloads[i].status = .downloading
            case .extracting:
                profileDownloads[i].status = .extracting
            case .completed:
                profileDownloads[i].status = .completed
            case .failed:
                profileDownloads[i].status = .failed
            }
        }

        // Animate out completed/failed downloads one at a time, top to bottom
        // Each item: swipe out, pause, then next item
        let completedIndices = profileDownloads.enumerated()
            .filter { $0.element.status == .completed || $0.element.status == .failed }
            .filter { !$0.element.isDismissing }
            .filter { !profileDownloadsScheduledForRemoval.contains($0.element.id) }
            .map { (index: $0.offset, id: $0.element.id) }

        for (order, item) in completedIndices.enumerated() {
            profileDownloadsScheduledForRemoval.insert(item.id)
            Task { @MainActor in
                // Initial delay before first item, then sequential timing
                // First at 2s, second at 3.5s, third at 5s (1.5s apart each)
                let delay = 2.0 + (Double(order) * 1.5)
                try? await Task.sleep(for: .seconds(delay))

                // Remove with Poof animation
                withAnimation {
                    profileDownloads.removeAll { $0.id == item.id }
                }
                profileDownloadsScheduledForRemoval.remove(item.id)
            }
        }
    }

    // MARK: - Modpack Export/Import

    /// Create a modpack from the current state
    func createModpack(name: String, author: String, description: String) -> Modpack {
        Modpack.fromCurrentState(
            name: name,
            author: author,
            description: description,
            mods: mods,
            loadOrder: modLoadOrder,
            modsDirectory: modsDirectory
        )
    }

    /// Export a modpack to a file
    func exportModpack(_ modpack: Modpack, to url: URL) {
        do {
            try modpackManager.exportModpack(modpack, to: url)
            statusMessage = "Modpack '\(modpack.name)' exported"
        } catch {
            statusMessage = "Error exporting modpack: \(error.localizedDescription)"
        }
    }

    /// Import and install a modpack from a file
    func importModpack(from url: URL) async {
        do {
            let modpack = try modpackManager.importModpack(from: url)
            statusMessage = "Importing modpack '\(modpack.name)'..."

            // Install mods from the modpack
            let result = await modpackManager.installModpack(
                modpack,
                modsDirectory: modsDirectory
            ) { [weak self] entry in
                guard let self = self, let modId = entry.gameBananaModId else { return false }

                // Fetch mod files and download the first one
                do {
                    let files = try await GameBananaAPI.shared.fetchModFiles(modId: modId)
                    guard let file = files.first else { return false }

                    let modName = entry.gameBananaName ?? entry.folderName
                    await self.downloadManager.downloadFile(file, modName: modName, modId: modId, isProfileDownload: true)
                    return true
                } catch {
                    print("Error downloading mod \(entry.folderName): \(error)")
                    return false
                }
            }

            // Apply load order from modpack
            modLoadOrder = modpack.loadOrder
            syncLoadOrderToConfig()

            await loadMods()

            // Apply individual mod states from modpack (if available)
            if let modStates = modpack.modStates {
                for mod in mods {
                    if let shouldBeEnabled = modStates[mod.stableId], shouldBeEnabled != mod.isEnabled {
                        await toggleMod(mod)
                    }
                }
            }

            statusMessage = "Imported '\(modpack.name)': \(result.installed) installed, \(result.skipped) skipped, \(result.failed) failed"

            // Store modpack for potential profile creation and notify user
            pendingModpackProfile = modpack
            addNotification("Modpack '\(modpack.name)' imported. Click here to save as profile.", type: .success)
        } catch {
            statusMessage = "Error importing modpack: \(error.localizedDescription)"
        }
    }

    // MARK: - Modpack to Profile Conversion

    /// Create a profile from the pending imported modpack
    func createProfileFromModpack() {
        guard let modpack = pendingModpackProfile else { return }

        // Create profile from current mod state (which now includes the imported mods)
        profileManager.saveCurrentState(
            name: modpack.name,
            mods: mods,
            loadOrder: modLoadOrder,
            modsDirectory: modsDirectory
        )

        addNotification("Profile '\(modpack.name)' created from modpack", type: .success)
        pendingModpackProfile = nil
        showModpackProfilePopover = false
    }

    /// Dismiss the modpack profile prompt without creating a profile
    func dismissModpackProfilePrompt() {
        pendingModpackProfile = nil
        showModpackProfilePopover = false
    }
}
