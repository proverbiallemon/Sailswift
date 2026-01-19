import Foundation

/// Service for managing the Ship of Harkinian configuration file
class GameConfigService {
    private let configURL: URL

    init(configURL: URL = PathConstants.gameConfigFile) {
        self.configURL = configURL
    }

    /// Enable AltAssets in the configuration
    func enableAltAssets() throws {
        var config = try loadConfig()

        if config.cvars == nil {
            config.cvars = CVars(gSettings: GSettings(altAssets: 1))
        } else if config.cvars?.gSettings == nil {
            config.cvars?.gSettings = GSettings(altAssets: 1)
        } else {
            config.cvars?.gSettings?.altAssets = 1
        }

        try saveConfig(config)
    }

    /// Get the mod load order from the configuration
    /// Returns an array of mod names in load order (earlier = lower priority)
    func getModLoadOrder() throws -> [String] {
        let config = try loadConfig()
        guard let enabledMods = config.cvars?.gSettings?.enabledMods, !enabledMods.isEmpty else {
            return []
        }
        return enabledMods.components(separatedBy: "|")
    }

    /// Set the mod load order in the configuration
    /// - Parameter order: Array of mod names in load order (earlier = lower priority)
    func setModLoadOrder(_ order: [String]) throws {
        var config = try loadConfig()

        if config.cvars == nil {
            config.cvars = CVars(gSettings: GSettings())
        } else if config.cvars?.gSettings == nil {
            config.cvars?.gSettings = GSettings()
        }

        config.cvars?.gSettings?.enabledMods = order.joined(separator: "|")
        try saveConfig(config)
    }

    // MARK: - Private Helpers

    private func loadConfig() throws -> GameConfig {
        if FileManager.default.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(GameConfig.self, from: data)
        }
        return GameConfig(cvars: CVars(gSettings: GSettings()))
    }

    private func saveConfig(_ config: GameConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL)
    }
}

struct GameConfig: Codable {
    var cvars: CVars?
    enum CodingKeys: String, CodingKey {
        case cvars = "CVars"
    }
}

struct CVars: Codable {
    var gSettings: GSettings?
}

struct GSettings: Codable {
    var altAssets: Int?
    var enabledMods: String?
    enum CodingKeys: String, CodingKey {
        case altAssets = "AltAssets"
        case enabledMods = "EnabledMods"
    }
}
