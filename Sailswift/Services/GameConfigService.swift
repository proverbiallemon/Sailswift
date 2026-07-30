import Foundation

/// Service for managing the Ship of Harkinian configuration file
///
/// The config file is owned by the game and contains many settings Sailswift
/// does not model (window, controllers, enhancements, randomizer, ...).
/// All writes therefore mutate the JSON in place and only ever touch
/// `CVars.gSettings.AltAssets` and `CVars.gSettings.EnabledMods`.
class GameConfigService {
    private let configURL: URL

    init(configURL: URL = PathConstants.gameConfigFile) {
        self.configURL = configURL
    }

    /// Enable AltAssets in the configuration
    func enableAltAssets() throws {
        try updateGSettings { gSettings in
            gSettings["AltAssets"] = 1
        }
    }

    /// Get the mod load order from the configuration
    /// Returns an array of mod names in load order (earlier = lower priority)
    func getModLoadOrder() throws -> [String] {
        let root = try loadRoot()
        guard let cvars = root["CVars"] as? [String: Any],
              let gSettings = cvars["gSettings"] as? [String: Any],
              let enabledMods = gSettings["EnabledMods"] as? String,
              !enabledMods.isEmpty else {
            return []
        }
        // Filter out empty strings that could result from leading/trailing/consecutive pipes
        return enabledMods.components(separatedBy: "|").filter { !$0.isEmpty }
    }

    /// Set the mod load order in the configuration
    /// - Parameter order: Array of mod names in load order (earlier = lower priority)
    func setModLoadOrder(_ order: [String]) throws {
        // Sanitize mod names: replace pipe characters to prevent parsing issues,
        // and filter out empty strings
        let sanitizedOrder = order
            .filter { !$0.isEmpty }
            .map { $0.replacingOccurrences(of: "|", with: "-") }

        try updateGSettings { gSettings in
            gSettings["EnabledMods"] = sanitizedOrder.joined(separator: "|")
        }
    }

    // MARK: - Private Helpers

    private func loadRoot() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: configURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return root
    }

    private func updateGSettings(_ mutate: (inout [String: Any]) -> Void) throws {
        var root = try loadRoot()
        var cvars = root["CVars"] as? [String: Any] ?? [:]
        var gSettings = cvars["gSettings"] as? [String: Any] ?? [:]
        mutate(&gSettings)
        cvars["gSettings"] = gSettings
        root["CVars"] = cvars

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL)
    }
}
