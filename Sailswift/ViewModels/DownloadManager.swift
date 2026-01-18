import Foundation
import SwiftUI

/// Represents a download in progress
struct Download: Identifiable {
    let id = UUID()
    let filename: String
    let modName: String
    let fileId: Int
    var progress: Double = 0
    var status: DownloadStatus = .pending

    enum DownloadStatus {
        case pending, downloading, extracting, completed, failed
    }
}

/// Manager for downloading mods from GameBanana
@MainActor
class DownloadManager: ObservableObject {
    @Published var downloads: [Download] = []
    @Published var currentDownload: Download?

    private let api = GameBananaAPI.shared
    private let fileService = FileService.shared
    private let session: URLSession

    /// Callback to notify AppState of download completion
    var onDownloadComplete: ((Bool, String) -> Void)?

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Sailswift/1.0"]
        self.session = URLSession(configuration: config)
    }

    /// Handle a download request from the shipofharkinian:// URL scheme
    func downloadFromURLScheme(itemId: String, itemType: String, fileId: String) async {
        print("[DownloadManager] Processing URL scheme download: itemId=\(itemId), fileId=\(fileId)")

        guard let fileIdInt = Int(fileId) else {
            showResult(success: false, message: "Invalid file ID: \(fileId)")
            return
        }

        do {
            guard let file = try await api.fetchFileInfo(fileId: fileIdInt) else {
                showResult(success: false, message: "Could not find file information")
                return
            }
            // Use filename without extension as mod name for URL scheme downloads
            let modName = (file.filename as NSString).deletingPathExtension
            await downloadFile(file, modName: modName)
        } catch {
            showResult(success: false, message: "Failed to get file info: \(error.localizedDescription)")
        }
    }

    /// Download a file from GameBanana
    func downloadFile(_ file: GameBananaFile, modName: String) async {
        var download = Download(filename: file.filename, modName: modName, fileId: file.fileId)
        download.status = .downloading
        currentDownload = download
        downloads.append(download)

        do {
            print("[DownloadManager] Starting download: \(file.downloadURL)")
            let (data, response) = try await session.data(from: file.downloadURL)

            if let httpResponse = response as? HTTPURLResponse {
                print("[DownloadManager] Response status: \(httpResponse.statusCode)")
            }
            print("[DownloadManager] Downloaded \(data.count) bytes")

            // Save to temp file
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempFile = tempDir.appendingPathComponent(file.filename)
            try data.write(to: tempFile)
            print("[DownloadManager] Saved to temp: \(tempFile.path)")

            updateDownloadStatus(fileId: file.fileId, status: .extracting)

            // Handle the downloaded file
            let installedCount = try await handleDownloadedFile(tempFile, modName: modName)

            // Clean up temp directory
            try? FileManager.default.removeItem(at: tempDir)

            updateDownloadStatus(fileId: file.fileId, status: .completed)

            if installedCount > 0 {
                let message = installedCount == 1
                    ? "Installed to \(sanitizeFolderName(modName))/"
                    : "Installed \(installedCount) files to \(sanitizeFolderName(modName))/"
                showResult(success: true, message: message)
            } else {
                showResult(success: false, message: "No mod files found in archive")
            }

        } catch {
            print("[DownloadManager] Error: \(error)")
            updateDownloadStatus(fileId: file.fileId, status: .failed)
            showResult(success: false, message: "Download failed: \(error.localizedDescription)")
        }

        currentDownload = nil
    }

    private func handleDownloadedFile(_ tempURL: URL, modName: String) async throws -> Int {
        let lowercasedFilename = tempURL.lastPathComponent.lowercased()
        let folderName = sanitizeFolderName(modName)
        let modFolder = PathConstants.modsDirectory.appendingPathComponent(folderName)

        // If it's directly a mod file, move it to a subfolder
        if lowercasedFilename.hasSuffix(".otr") || lowercasedFilename.hasSuffix(".o2r") {
            try FileManager.default.createDirectory(at: modFolder, withIntermediateDirectories: true)
            let destFile = modFolder.appendingPathComponent(tempURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destFile.path) {
                try FileManager.default.removeItem(at: destFile)
            }
            try FileManager.default.moveItem(at: tempURL, to: destFile)
            print("[DownloadManager] Installed mod file to: \(destFile.path)")
            return 1
        }

        // If it's an archive, extract and find mod files
        if lowercasedFilename.hasSuffix(".zip") || lowercasedFilename.hasSuffix(".7z") {
            return try await extractAndInstallMods(from: tempURL, to: modFolder)
        }

        // Unknown file type - try to treat as archive
        return try await extractAndInstallMods(from: tempURL, to: modFolder)
    }

    private func extractAndInstallMods(from archiveURL: URL, to modFolder: URL) async throws -> Int {
        // Create temp extraction directory
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("extract_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: extractDir)
        }

        // Extract archive using ditto
        print("[DownloadManager] Extracting to: \(extractDir.path)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", archiveURL.path, extractDir.path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("[DownloadManager] ditto error: \(errorString)")
            throw DownloadError.extractionFailed
        }

        // Find all mod files recursively
        let modFiles = findModFiles(in: extractDir)
        print("[DownloadManager] Found \(modFiles.count) mod files")

        if modFiles.isEmpty {
            return 0
        }

        // Create mod folder and move files
        try FileManager.default.createDirectory(at: modFolder, withIntermediateDirectories: true)

        var installedCount = 0
        for modFile in modFiles {
            let filename = modFile.lastPathComponent
            var destFile = modFolder.appendingPathComponent(filename)

            // Handle duplicates
            if FileManager.default.fileExists(atPath: destFile.path) {
                let baseName = (filename as NSString).deletingPathExtension
                let ext = (filename as NSString).pathExtension
                var counter = 1
                while FileManager.default.fileExists(atPath: destFile.path) {
                    destFile = modFolder.appendingPathComponent("\(baseName)_\(counter).\(ext)")
                    counter += 1
                }
            }

            try FileManager.default.moveItem(at: modFile, to: destFile)
            print("[DownloadManager] Installed: \(destFile.lastPathComponent)")
            installedCount += 1
        }

        return installedCount
    }

    /// Find all mod files (.otr, .o2r) recursively in a directory
    private func findModFiles(in directory: URL) -> [URL] {
        var modFiles: [URL] = []
        let validExtensions = Set(["otr", "o2r"])

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            if validExtensions.contains(fileURL.pathExtension.lowercased()) {
                modFiles.append(fileURL)
            }
        }

        return modFiles
    }

    /// Sanitize folder name for filesystem
    private func sanitizeFolderName(_ name: String) -> String {
        var sanitized = name
        // Remove unsafe characters
        let unsafeChars = CharacterSet(charactersIn: "<>:\"/\\|?*")
        sanitized = sanitized.components(separatedBy: unsafeChars).joined()
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        // Limit length
        if sanitized.count > 50 {
            sanitized = String(sanitized.prefix(50)).trimmingCharacters(in: .whitespaces)
        }
        return sanitized.isEmpty ? "mod" : sanitized
    }

    private func updateDownloadStatus(fileId: Int, status: Download.DownloadStatus) {
        if let index = downloads.firstIndex(where: { $0.fileId == fileId }) {
            downloads[index].status = status
        }
        if currentDownload?.fileId == fileId {
            currentDownload?.status = status
        }
    }

    private func showResult(success: Bool, message: String) {
        onDownloadComplete?(success, message)
    }
}

enum DownloadError: LocalizedError {
    case extractionFailed

    var errorDescription: String? {
        switch self {
        case .extractionFailed: return "Failed to extract archive"
        }
    }
}
