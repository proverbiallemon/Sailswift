import Foundation

/// Information about an available mod update
struct ModUpdateInfo: Identifiable {
    let id: String  // folder path
    let folderPath: String
    let modName: String
    let gameBananaModId: Int
    let downloadedAt: Date
    let updatedAt: Date  // GameBanana's _tsDateUpdated

    var daysSinceDownload: Int {
        Calendar.current.dateComponents([.day], from: downloadedAt, to: Date()).day ?? 0
    }

    var daysSinceUpdate: Int {
        Calendar.current.dateComponents([.day], from: updatedAt, to: Date()).day ?? 0
    }
}

/// Service for checking installed mods for available updates
@MainActor
class ModUpdateChecker: ObservableObject {
    static let shared = ModUpdateChecker()

    @Published var updates: [String: ModUpdateInfo] = [:]  // folder path -> update info
    @Published var isChecking = false
    @Published var lastChecked: Date?
    @Published var statusMessage = ""

    private let api = GameBananaAPI.shared

    private init() {}

    /// Check all installed mods for updates
    func checkForUpdates(modsDirectory: URL) async {
        guard !isChecking else { return }

        isChecking = true
        statusMessage = "Scanning mods..."
        updates.removeAll()

        // Find all mod folders with metadata
        let modsWithMetadata = findModsWithMetadata(in: modsDirectory)

        if modsWithMetadata.isEmpty {
            statusMessage = "No mods with GameBanana metadata found"
            isChecking = false
            lastChecked = Date()
            return
        }

        statusMessage = "Checking \(modsWithMetadata.count) mods..."

        var checkedCount = 0
        var updatesFound = 0

        for (folderPath, metadata) in modsWithMetadata {
            guard let modId = metadata.gameBananaModId else { continue }

            do {
                // Small delay between API calls to be polite
                if checkedCount > 0 {
                    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
                }

                if let mod = try await api.fetchModDetails(modId: modId, itemType: "Mod") {
                    // Check if GameBanana's update date is newer than our download date
                    if let gbUpdatedAt = mod.dateUpdated, gbUpdatedAt > metadata.downloadedAt {
                        let relativePath = folderPath.replacingOccurrences(of: modsDirectory.path + "/", with: "")
                        let updateInfo = ModUpdateInfo(
                            id: relativePath,
                            folderPath: relativePath,
                            modName: metadata.gameBananaName,
                            gameBananaModId: modId,
                            downloadedAt: metadata.downloadedAt,
                            updatedAt: gbUpdatedAt
                        )
                        updates[relativePath] = updateInfo
                        updatesFound += 1
                    }
                }

                checkedCount += 1
                statusMessage = "Checked \(checkedCount)/\(modsWithMetadata.count)..."

            } catch {
                print("[UpdateChecker] Error checking mod \(modId): \(error)")
            }
        }

        lastChecked = Date()
        isChecking = false

        if updatesFound > 0 {
            statusMessage = "\(updatesFound) update\(updatesFound == 1 ? "" : "s") available"
        } else {
            statusMessage = "All mods up to date"
        }
    }

    /// Find all mod folders containing .sailswift.json metadata
    private func findModsWithMetadata(in directory: URL) -> [(String, ModMetadata)] {
        var results: [(String, ModMetadata)] = []

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return results
        }

        for case let folderURL as URL in enumerator {
            // Check if this folder has a .sailswift.json file
            if let metadata = ModMetadata.load(from: folderURL) {
                results.append((folderURL.path, metadata))
                // Don't descend into subfolders of a mod folder
                enumerator.skipDescendants()
            }
        }

        return results
    }

    /// Check if a specific mod folder has an update available
    func hasUpdate(for folderPath: String) -> Bool {
        updates[folderPath] != nil
    }

    /// Get update info for a specific mod folder
    func updateInfo(for folderPath: String) -> ModUpdateInfo? {
        updates[folderPath]
    }

    /// Clear update status for a folder (after user updates/dismisses)
    func clearUpdate(for folderPath: String) {
        updates.removeValue(forKey: folderPath)
    }
}
