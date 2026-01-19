import Foundation
import Sparkle

/// Service for managing automatic updates via Sparkle
@MainActor
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    private let updaterController: SPUStandardUpdaterController

    /// Whether the updater is able to check for updates
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    /// Whether to automatically check for updates
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Manually trigger an update check
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
