import Foundation

/// Service for managing the Ship of Harkinian configuration file
class GameConfigService {
    private let configURL: URL

    init(configURL: URL = PathConstants.gameConfigFile) {
        self.configURL = configURL
    }

    /// Enable AltAssets in the configuration
    func enableAltAssets() throws {
        var config: GameConfig

        if FileManager.default.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(GameConfig.self, from: data)
        } else {
            config = GameConfig(cvars: CVars(gSettings: GSettings(altAssets: 1)))
        }

        if config.cvars == nil {
            config.cvars = CVars(gSettings: GSettings(altAssets: 1))
        } else if config.cvars?.gSettings == nil {
            config.cvars?.gSettings = GSettings(altAssets: 1)
        } else {
            config.cvars?.gSettings?.altAssets = 1
        }

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
    enum CodingKeys: String, CodingKey {
        case altAssets = "AltAssets"
    }
}
