import Foundation

/// Constants for file paths used by the application
enum PathConstants {
    /// Ship of Harkinian application support directory
    static var sohAppSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.shipofharkinian.soh")
    }

    /// The mods directory
    static var modsDirectory: URL {
        sohAppSupportDirectory.appendingPathComponent("mods")
    }

    /// The game configuration file
    static var gameConfigFile: URL {
        sohAppSupportDirectory.appendingPathComponent("shipofharkinian.json")
    }

    /// Sailswift application support directory
    static var appSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sailswift")
    }

    /// Default game installation paths
    static var defaultGamePaths: [URL] {
        [
            URL(fileURLWithPath: "/Applications/soh.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/soh.app"),
            URL(fileURLWithPath: "/Applications/Ship of Harkinian.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Ship of Harkinian.app")
        ]
    }

    /// Ensure all required directories exist
    static func ensureDirectoriesExist() {
        let directories = [modsDirectory, appSupportDirectory]
        for directory in directories {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Find the game installation path
    static func findGamePath() -> URL? {
        for path in defaultGamePaths {
            if FileManager.default.fileExists(atPath: path.path) && validateGameInstallation(at: path) {
                return path
            }
        }
        return nil
    }

    /// Validate that a path contains a valid Ship of Harkinian installation
    static func validateGameInstallation(at path: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: path.path) else { return false }

        if path.pathExtension == "app" {
            let executablePaths = [
                path.appendingPathComponent("Contents/MacOS/soh"),
                path.appendingPathComponent("Contents/MacOS/SoH")
            ]
            for execPath in executablePaths {
                if FileManager.default.fileExists(atPath: execPath.path) {
                    return true
                }
            }
        }
        return false
    }
}
