import SwiftUI
import Combine

/// Represents a pending mod import from URL scheme
struct PendingImport: Identifiable {
    let id = UUID()
    let modId: String
    let itemType: String
    let fileId: String
    var mod: GameBananaMod?
    var file: GameBananaFile?
    var isLoading = true
    var error: String?
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

    // Import confirmation
    @Published var pendingImport: PendingImport?
    @Published var showImportConfirmation = false

    // MARK: - Settings

    @AppStorage("gamePath") var gamePath: String = ""
    @AppStorage("skipUpdateCheck") var skipUpdateCheck = false
    @AppStorage("enableAltAssets") var enableAltAssets = true
    @AppStorage("confirmDelete") var confirmDelete = true

    // MARK: - Managers

    let modManager = ModManager()
    let downloadManager = DownloadManager()
    let gameConfigService = GameConfigService()

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

        // Load mods
        Task {
            await loadMods()
        }
    }

    // MARK: - Mod Operations

    func loadMods() async {
        isLoading = true
        statusMessage = "Loading mods..."

        do {
            mods = try await modManager.loadMods(from: modsDirectory)
            statusMessage = "Loaded \(mods.count) mods"
        } catch {
            statusMessage = "Error loading mods: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func toggleMod(_ mod: Mod) async {
        do {
            try await modManager.toggleMod(mod)
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
            await loadMods()
            statusMessage = "Deleted \(mod.name)"
        } catch {
            statusMessage = "Error deleting mod: \(error.localizedDescription)"
        }
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
        pendingImport = PendingImport(modId: modId, itemType: itemType, fileId: fileId)
        showImportConfirmation = true

        // Fetch both mod and file details in parallel
        do {
            async let modTask = GameBananaAPI.shared.fetchModDetails(modId: Int(modId) ?? 0)
            async let fileTask = GameBananaAPI.shared.fetchFileInfo(fileId: Int(fileId) ?? 0)

            let (mod, file) = try await (modTask, fileTask)

            pendingImport?.mod = mod
            pendingImport?.file = file
            pendingImport?.isLoading = false

            if file == nil {
                pendingImport?.error = "Could not fetch file information"
            }
        } catch {
            pendingImport?.isLoading = false
            pendingImport?.error = error.localizedDescription
        }
    }

    /// Confirm and start the pending import
    func confirmImport() async {
        guard let pending = pendingImport, let file = pending.file else {
            showImportConfirmation = false
            pendingImport = nil
            return
        }

        showImportConfirmation = false
        let modName = pending.mod?.name ?? (file.filename as NSString).deletingPathExtension
        await downloadManager.downloadFile(file, modName: modName)
        pendingImport = nil
    }

    /// Cancel the pending import
    func cancelImport() {
        showImportConfirmation = false
        pendingImport = nil
    }
}
