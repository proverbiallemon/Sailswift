import XCTest

final class GameConfigServiceTests: XCTestCase {
    private var tempDir: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent("shipofharkinian.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// A realistic SoH config: many keys Sailswift doesn't model and must never touch.
    private let fullConfig = """
    {
      "ConfigVersion": "1.0",
      "Window": {"Width": 1920, "Height": 1080, "Fullscreen": {"Enabled": false}},
      "CVars": {
        "gSettings": {
          "AltAssets": 0,
          "EnabledMods": "ModA|ModB",
          "BootSequence": 1,
          "Controllers": {"Deadzone": 0.2}
        },
        "gEnhancements": {"FastText": 1, "MMBunnyHood": 1},
        "gRandoSettings": {"Seed": "ABCDEF"}
      },
      "Audio": {"Master": 0.8}
    }
    """

    private func writeFullConfig() throws {
        try fullConfig.data(using: .utf8)!.write(to: configURL)
    }

    private func readConfigJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: configURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSetModLoadOrderPreservesUnknownKeys() throws {
        try writeFullConfig()
        let service = GameConfigService(configURL: configURL)

        try service.setModLoadOrder(["ModB", "ModA"])

        let json = try readConfigJSON()
        XCTAssertEqual(json["ConfigVersion"] as? String, "1.0", "top-level keys must survive")
        XCTAssertNotNil(json["Window"], "Window settings must survive a load-order save")
        XCTAssertNotNil(json["Audio"], "Audio settings must survive")
        let cvars = try XCTUnwrap(json["CVars"] as? [String: Any])
        XCTAssertNotNil(cvars["gEnhancements"], "gEnhancements must survive")
        XCTAssertNotNil(cvars["gRandoSettings"], "gRandoSettings must survive")
        let gSettings = try XCTUnwrap(cvars["gSettings"] as? [String: Any])
        XCTAssertEqual(gSettings["EnabledMods"] as? String, "ModB|ModA")
        XCTAssertNotNil(gSettings["BootSequence"], "sibling gSettings keys must survive")
        XCTAssertNotNil(gSettings["Controllers"], "controller settings must survive")
    }

    func testEnableAltAssetsPreservesUnknownKeys() throws {
        try writeFullConfig()
        let service = GameConfigService(configURL: configURL)

        try service.enableAltAssets()

        let json = try readConfigJSON()
        XCTAssertNotNil(json["Window"], "Window settings must survive enabling AltAssets")
        let cvars = try XCTUnwrap(json["CVars"] as? [String: Any])
        XCTAssertNotNil(cvars["gEnhancements"], "gEnhancements must survive")
        let gSettings = try XCTUnwrap(cvars["gSettings"] as? [String: Any])
        XCTAssertEqual(gSettings["AltAssets"] as? Int, 1)
        XCTAssertEqual(gSettings["EnabledMods"] as? String, "ModA|ModB", "EnabledMods must be untouched")
    }

    func testGetModLoadOrderReadsExistingEntries() throws {
        try writeFullConfig()
        let service = GameConfigService(configURL: configURL)

        XCTAssertEqual(try service.getModLoadOrder(), ["ModA", "ModB"])
    }

    func testGetModLoadOrderFiltersEmptyComponents() throws {
        try """
        {"CVars": {"gSettings": {"EnabledMods": "|ModA||ModB|"}}}
        """.data(using: .utf8)!.write(to: configURL)
        let service = GameConfigService(configURL: configURL)

        XCTAssertEqual(try service.getModLoadOrder(), ["ModA", "ModB"])
    }

    func testSetModLoadOrderCreatesFileWhenMissing() throws {
        let service = GameConfigService(configURL: configURL)

        try service.setModLoadOrder(["ModA"])

        let json = try readConfigJSON()
        let cvars = try XCTUnwrap(json["CVars"] as? [String: Any])
        let gSettings = try XCTUnwrap(cvars["gSettings"] as? [String: Any])
        XCTAssertEqual(gSettings["EnabledMods"] as? String, "ModA")
    }

    func testSetModLoadOrderSanitizesPipesInNames() throws {
        try writeFullConfig()
        let service = GameConfigService(configURL: configURL)

        try service.setModLoadOrder(["Bad|Name", "", "Good"])

        XCTAssertEqual(try service.getModLoadOrder(), ["Bad-Name", "Good"])
    }
}
