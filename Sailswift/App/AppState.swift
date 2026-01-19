 import SwiftUI
import Combine

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

        // Set up download completion callback
        downloadManager.onDownloadComplete = { [weak self] success, message in
            Task { @MainActor in
                self?.downloadAlertMessage = message
                self?.showDownloadAlert = true
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
            try await modManager.toggleModsInFolder(folderPath)
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

    /// Cancel the pending import (but keep popover open if there are active downloads)
    func cancelImport() {
        showImportConfirmation = false
        pendingImport = nil
        // Only close popover if there are no active downloads
        if downloadManager.downloads.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
            showDownloadPopover = false
        }
    }

    /// Toggle the download popover visibility
    func toggleDownloadPopover() {
        showDownloadPopover.toggle()
    }

    /// Close the download popover and clear completed downloads
    func closeDownloadPopover() {
        showDownloadPopover = false
        // Clear completed/failed downloads when closing
        downloadManager.downloads.removeAll { $0.status == .completed || $0.status == .failed }
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
}
