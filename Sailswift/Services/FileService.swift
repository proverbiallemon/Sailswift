import Foundation
import AppKit

/// Service for file operations
class FileService {
    static let shared = FileService()
    private let fileManager = FileManager.default

    private init() {}

    /// List all mod files in a directory recursively
    func listModFiles(in directory: URL) throws -> [URL] {
        var modFiles: [URL] = []

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw FileServiceError.cannotEnumerateDirectory(directory)
        }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ModFileExtension.allExtensions.contains(ext) {
                modFiles.append(fileURL)
            }
        }

        return modFiles
    }

    /// Rename a file (used for toggling mod state)
    func renameFile(from source: URL, to destination: URL) throws {
        try fileManager.moveItem(at: source, to: destination)
    }

    /// Delete a file or directory
    func delete(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    /// Check if a path exists
    func exists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    /// Create a directory if it doesn't exist
    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Copy a file to the mods directory
    func copyToMods(from source: URL, subfolder: String? = nil) throws -> URL {
        var destination = PathConstants.modsDirectory

        if let subfolder = subfolder, !subfolder.isEmpty {
            destination = destination.appendingPathComponent(subfolder)
            try createDirectory(at: destination)
        }

        let destinationFile = destination.appendingPathComponent(source.lastPathComponent)

        if exists(at: destinationFile) {
            try delete(at: destinationFile)
        }

        try fileManager.copyItem(at: source, to: destinationFile)
        return destinationFile
    }

    /// Move a file to the mods directory
    func moveToMods(from source: URL, subfolder: String? = nil) throws -> URL {
        var destination = PathConstants.modsDirectory

        if let subfolder = subfolder, !subfolder.isEmpty {
            destination = destination.appendingPathComponent(subfolder)
            try createDirectory(at: destination)
        }

        let destinationFile = destination.appendingPathComponent(source.lastPathComponent)

        if exists(at: destinationFile) {
            try delete(at: destinationFile)
        }

        try fileManager.moveItem(at: source, to: destinationFile)
        return destinationFile
    }

    /// Get the relative path from base directory
    func relativePath(of url: URL, from base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path

        if filePath.hasPrefix(basePath) {
            var relative = String(filePath.dropFirst(basePath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative
        }
        return url.lastPathComponent
    }

    /// Open a folder in Finder
    func openInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    /// Reveal a file in Finder
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum FileServiceError: LocalizedError {
    case cannotEnumerateDirectory(URL)

    var errorDescription: String? {
        switch self {
        case .cannotEnumerateDirectory(let url):
            return "Cannot enumerate directory: \(url.path)"
        }
    }
}
