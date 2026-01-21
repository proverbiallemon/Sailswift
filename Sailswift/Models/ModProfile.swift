import Foundation

/// Info about a mod in a profile
struct ProfileModInfo: Codable, Hashable {
    let isEnabled: Bool
    let gameBananaModId: Int?
    let gameBananaName: String?
    let folderName: String  // Top-level folder name for display
}

/// A saved mod profile/configuration
struct ModProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var modInfos: [String: ProfileModInfo]  // stableId -> mod info (includes GameBanana ID for downloads)
    var loadOrder: [String]  // mod names in priority order
    var createdAt: Date
    var updatedAt: Date

    // Legacy support for old profiles that only had modStates
    var modStates: [String: Bool]?

    init(name: String, modInfos: [String: ProfileModInfo] = [:], loadOrder: [String] = []) {
        self.id = UUID()
        self.name = name
        self.modInfos = modInfos
        self.modStates = nil
        self.loadOrder = loadOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func fromCurrentState(mods: [Mod], loadOrder: [String], name: String, modsDirectory: URL) -> ModProfile {
        var infos: [String: ProfileModInfo] = [:]
        var folderMetadataCache: [String: ModMetadata] = [:]

        // Save EVERY mod individually (not just one per folder)
        for mod in mods {
            // Get top-level folder name
            let folderName = mod.folderPath.isEmpty ? mod.name : mod.folderPath.components(separatedBy: "/").first ?? mod.name

            // Try to get GameBanana ID from metadata (cache per folder to avoid repeated disk reads)
            var gameBananaModId: Int? = nil
            var gameBananaName: String? = nil

            if !mod.folderPath.isEmpty {
                if let cachedMetadata = folderMetadataCache[folderName] {
                    gameBananaModId = cachedMetadata.gameBananaModId
                    gameBananaName = cachedMetadata.gameBananaName
                } else {
                    let folderURL = modsDirectory.appendingPathComponent(folderName)
                    if let metadata = ModMetadata.load(from: folderURL) {
                        folderMetadataCache[folderName] = metadata
                        gameBananaModId = metadata.gameBananaModId
                        gameBananaName = metadata.gameBananaName
                    }
                }
            }

            infos[mod.stableId] = ProfileModInfo(
                isEnabled: mod.isEnabled,
                gameBananaModId: gameBananaModId,
                gameBananaName: gameBananaName,
                folderName: folderName
            )
        }

        return ModProfile(name: name, modInfos: infos, loadOrder: loadOrder)
    }

    var enabledCount: Int {
        if !modInfos.isEmpty {
            return modInfos.values.filter { $0.isEnabled }.count
        }
        // Legacy fallback
        return modStates?.values.filter { $0 }.count ?? 0
    }

    var totalCount: Int {
        if !modInfos.isEmpty {
            return modInfos.count
        }
        // Legacy fallback
        return modStates?.count ?? 0
    }

    /// Get mods that have GameBanana IDs (can be downloaded)
    var downloadableMods: [(stableId: String, info: ProfileModInfo)] {
        modInfos.compactMap { (stableId, info) in
            info.gameBananaModId != nil ? (stableId, info) : nil
        }
    }
}

/// Manager for mod profiles
@MainActor
class ModProfileManager: ObservableObject {
    static let shared = ModProfileManager()

    @Published var profiles: [ModProfile] = []
    @Published var activeProfileId: UUID?

    private let profilesFile: URL

    private init() {
        self.profilesFile = PathConstants.appSupportDirectory.appendingPathComponent("profiles.json")
        loadProfiles()
    }

    func loadProfiles() {
        guard FileManager.default.fileExists(atPath: profilesFile.path) else {
            profiles = []
            return
        }
        do {
            let data = try Data(contentsOf: profilesFile)
            profiles = try JSONDecoder().decode([ModProfile].self, from: data)
        } catch {
            print("Error loading profiles: \(error)")
            profiles = []
        }
    }

    func saveProfiles() {
        do {
            try FileManager.default.createDirectory(
                at: PathConstants.appSupportDirectory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: profilesFile)
        } catch {
            print("Error saving profiles: \(error)")
        }
    }

    /// Save current mod state as a new profile
    func saveCurrentState(name: String, mods: [Mod], loadOrder: [String], modsDirectory: URL) {
        let profile = ModProfile.fromCurrentState(mods: mods, loadOrder: loadOrder, name: name, modsDirectory: modsDirectory)
        profiles.append(profile)
        saveProfiles()
    }

    /// Update an existing profile with current state
    func updateProfile(id: UUID, mods: [Mod], loadOrder: [String], modsDirectory: URL) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let updated = ModProfile.fromCurrentState(mods: mods, loadOrder: loadOrder, name: profiles[index].name, modsDirectory: modsDirectory)
        profiles[index].modInfos = updated.modInfos
        profiles[index].modStates = nil  // Clear legacy data
        profiles[index].loadOrder = updated.loadOrder
        profiles[index].updatedAt = Date()
        saveProfiles()
    }

    /// Rename a profile
    func renameProfile(id: UUID, newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = newName
        profiles[index].updatedAt = Date()
        saveProfiles()
    }

    /// Delete a profile
    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = nil
        }
        saveProfiles()
    }

    /// Get a profile by ID
    func profile(withId id: UUID) -> ModProfile? {
        profiles.first { $0.id == id }
    }
}
