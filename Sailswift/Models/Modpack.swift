import Foundation

/// A shareable modpack containing mod references and configuration
struct Modpack: Codable {
    let name: String
    let author: String
    let description: String
    let createdAt: Date
    let mods: [ModpackEntry]
    let loadOrder: [String]

    /// File extension for modpack files
    static let fileExtension = "sailswiftpack"

    /// Create a modpack from the current mod configuration
    static func fromCurrentState(
        name: String,
        author: String,
        description: String,
        mods: [Mod],
        loadOrder: [String],
        modsDirectory: URL
    ) -> Modpack {
        let entries = mods.map { mod -> ModpackEntry in
            // Try to get GameBanana ID from metadata
            var gameBananaModId: Int? = nil
            var gameBananaName: String? = nil

            if !mod.folderPath.isEmpty {
                let topLevelFolder = mod.folderPath.components(separatedBy: "/").first ?? mod.folderPath
                let folderURL = modsDirectory.appendingPathComponent(topLevelFolder)
                if let metadata = ModMetadata.load(from: folderURL) {
                    gameBananaModId = metadata.gameBananaModId
                    gameBananaName = metadata.gameBananaName
                }
            }

            return ModpackEntry(
                folderName: mod.folderPath.isEmpty ? mod.name : mod.folderPath.components(separatedBy: "/").first ?? mod.name,
                modName: mod.name,
                isEnabled: mod.isEnabled,
                gameBananaModId: gameBananaModId,
                gameBananaName: gameBananaName
            )
        }

        // Deduplicate entries by folder name
        var seenFolders = Set<String>()
        let uniqueEntries = entries.filter { entry in
            if seenFolders.contains(entry.folderName) {
                return false
            }
            seenFolders.insert(entry.folderName)
            return true
        }

        return Modpack(
            name: name,
            author: author,
            description: description,
            createdAt: Date(),
            mods: uniqueEntries,
            loadOrder: loadOrder
        )
    }
}

/// A single mod entry in a modpack
struct ModpackEntry: Codable, Identifiable {
    let folderName: String
    let modName: String
    let isEnabled: Bool
    let gameBananaModId: Int?
    let gameBananaName: String?

    var id: String { folderName }

    /// Whether this mod can be downloaded from GameBanana
    var canDownload: Bool {
        gameBananaModId != nil
    }
}

/// Manager for modpack export/import operations
@MainActor
class ModpackManager: ObservableObject {
    static let shared = ModpackManager()

    @Published var isExporting = false
    @Published var isImporting = false
    @Published var importProgress: String = ""

    private init() {}

    /// Export a modpack to a file
    func exportModpack(_ modpack: Modpack, to url: URL) throws {
        isExporting = true
        defer { isExporting = false }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(modpack)
        try data.write(to: url)
    }

    /// Import a modpack from a file
    func importModpack(from url: URL) throws -> Modpack {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Modpack.self, from: data)
    }

    /// Install mods from a modpack
    func installModpack(
        _ modpack: Modpack,
        modsDirectory: URL,
        onModDownload: @escaping (ModpackEntry) async -> Bool
    ) async -> (installed: Int, skipped: Int, failed: Int) {
        isImporting = true
        defer { isImporting = false }

        var installed = 0
        var skipped = 0
        var failed = 0

        // Track which GameBanana mod IDs we've already queued to prevent duplicate downloads
        var downloadedModIds: Set<Int> = []

        for entry in modpack.mods {
            // Check if mod already exists locally
            let localPath = modsDirectory.appendingPathComponent(entry.folderName)
            if FileManager.default.fileExists(atPath: localPath.path) {
                importProgress = "Found \(entry.folderName) (already installed)"
                skipped += 1
                continue
            }

            // Try to download from GameBanana
            // Only download each mod ID once (multiple entries may share the same ID)
            if let modId = entry.gameBananaModId, !downloadedModIds.contains(modId) {
                downloadedModIds.insert(modId)
                importProgress = "Downloading \(entry.gameBananaName ?? entry.folderName)..."
                let success = await onModDownload(entry)
                if success {
                    installed += 1
                } else {
                    failed += 1
                }
            } else if entry.gameBananaModId == nil {
                importProgress = "Skipping \(entry.folderName) (no GameBanana ID)"
                skipped += 1
            }
            // If modId was already downloaded, silently skip (don't count as skipped)
        }

        importProgress = ""
        return (installed, skipped, failed)
    }
}
