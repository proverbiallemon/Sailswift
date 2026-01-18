import Foundation

/// A saved mod profile/configuration
struct ModProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var modStates: [String: Bool]  // relativePath -> isEnabled
    var createdAt: Date
    var updatedAt: Date

    init(name: String, modStates: [String: Bool] = [:]) {
        self.id = UUID()
        self.name = name
        self.modStates = modStates
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func fromMods(_ mods: [Mod], name: String) -> ModProfile {
        var states: [String: Bool] = [:]
        for mod in mods {
            states[mod.relativePath] = mod.isEnabled
        }
        return ModProfile(name: name, modStates: states)
    }
}

/// Manager for mod profiles
class ModProfileManager: ObservableObject {
    @Published var profiles: [ModProfile] = []
    private let profilesFile: URL

    init() {
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

    func saveCurrentState(as name: String, mods: [Mod]) {
        if let existingIndex = profiles.firstIndex(where: { $0.name == name }) {
            var updated = ModProfile.fromMods(mods, name: name)
            updated.updatedAt = Date()
            profiles[existingIndex] = updated
        } else {
            profiles.append(ModProfile.fromMods(mods, name: name))
        }
        saveProfiles()
    }
}
