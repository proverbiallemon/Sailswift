import Foundation
import SwiftUI
import CryptoKit

/// Represents a download in progress
struct Download: Identifiable {
    let id = UUID()
    let filename: String
    let modName: String
    let fileId: Int
    let modId: Int?
    var progress: Double = 0
    var totalBytes: Int64 = 0
    var downloadedBytes: Int64 = 0
    var status: DownloadStatus = .pending
    var statusMessage: String = "Preparing..."

    enum DownloadStatus {
        case pending, downloading, extracting, completed, failed
    }

    var progressText: String {
        switch status {
        case .pending:
            return "Waiting..."
        case .downloading:
            if totalBytes > 0 {
                let downloaded = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                return "\(downloaded) / \(total)"
            }
            return "Downloading..."
        case .extracting:
            return "Extracting..."
        case .completed:
            return "Complete"
        case .failed:
            return statusMessage
        }
    }
}

/// Helper class to handle URLSession download delegate callbacks
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((Int64, Int64) -> Void)?
    var onComplete: ((URL?, Error?) -> Void)?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onComplete?(location, nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onComplete?(nil, error)
        }
    }
}

/// Manager for downloading mods from GameBanana
@MainActor
class DownloadManager: ObservableObject {
    @Published var downloads: [Download] = []
    @Published var currentDownload: Download?

    private let api = GameBananaAPI.shared
    private let fileService = FileService.shared

    /// Callback to notify AppState of download completion
    var onDownloadComplete: ((Bool, String) -> Void)?

    /// Callback when 7-Zip is required but not installed
    var on7zMissing: (() -> Void)?

    /// Callback when unrar is required (RAR uses unsupported compression)
    var onUnrarMissing: (() -> Void)?

    init() {}

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

    /// Download a file from GameBanana using fast URLSessionDownloadTask
    func downloadFile(_ file: GameBananaFile, modName: String, modId: Int? = nil) async {
        var download = Download(filename: file.filename, modName: modName, fileId: file.fileId, modId: modId)
        download.status = .downloading
        download.statusMessage = "Starting download..."
        currentDownload = download
        downloads.append(download)

        do {
            // Use URLSessionDownloadTask for browser-equivalent download speed
            let tempFile = try await downloadWithProgress(
                url: file.downloadURL,
                filename: file.filename,
                fileId: file.fileId
            )

            print("[DownloadManager] Downloaded to temp: \(tempFile.path)")

            // Security: Verify MD5 checksum if provided
            if !file.md5.isEmpty {
                let data = try Data(contentsOf: tempFile)
                let computedMD5 = Insecure.MD5.hash(data: data)
                let computedMD5String = computedMD5.map { String(format: "%02hhx", $0) }.joined()
                if computedMD5String.lowercased() != file.md5.lowercased() {
                    try? FileManager.default.removeItem(at: tempFile)
                    throw DownloadError.checksumMismatch
                }
            }

            updateDownloadStatus(fileId: file.fileId, status: .extracting, message: "Extracting files...")

            // Handle the downloaded file
            let installedCount = try await handleDownloadedFile(tempFile, modName: modName, modId: modId)

            // Clean up temp directory (parent of tempFile)
            try? FileManager.default.removeItem(at: tempFile.deletingLastPathComponent())

            if installedCount > 0 {
                let message = installedCount == 1
                    ? "Installed to \(sanitizeFolderName(modName))/"
                    : "Installed \(installedCount) files to \(sanitizeFolderName(modName))/"
                updateDownloadStatus(fileId: file.fileId, status: .completed, message: message)
                showResult(success: true, message: message)
            } else {
                updateDownloadStatus(fileId: file.fileId, status: .failed, message: "No mod files found")
                showResult(success: false, message: "No mod files found in archive")
            }

        } catch DownloadError.sevenZipNotFound {
            updateDownloadStatus(fileId: file.fileId, status: .failed, message: "7-Zip required")
            on7zMissing?()
        } catch DownloadError.rarMethodUnsupported {
            updateDownloadStatus(fileId: file.fileId, status: .failed, message: "unrar required")
            onUnrarMissing?()
        } catch {
            updateDownloadStatus(fileId: file.fileId, status: .failed, message: error.localizedDescription)
            showResult(success: false, message: "Download failed: \(error.localizedDescription)")
        }

        // Don't clear currentDownload here - keep it to show completion status
        // The user will dismiss the popover which clears it via AppState.cancelImport()
    }

    private func handleDownloadedFile(_ tempURL: URL, modName: String, modId: Int?) async throws -> Int {
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

            // Save metadata
            saveMetadata(modName: modName, modId: modId, to: modFolder)

            return 1
        }

        // If it's an archive, extract and find mod files
        let isZip = lowercasedFilename.hasSuffix(".zip")
        let is7z = lowercasedFilename.hasSuffix(".7z")
        let isRar = lowercasedFilename.hasSuffix(".rar")
        if isZip || is7z || isRar {
            let count = try await extractAndInstallMods(from: tempURL, to: modFolder)
            if count > 0 {
                saveMetadata(modName: modName, modId: modId, to: modFolder)
            }
            return count
        }

        // Unknown file type - try to treat as archive
        let count = try await extractAndInstallMods(from: tempURL, to: modFolder)
        if count > 0 {
            saveMetadata(modName: modName, modId: modId, to: modFolder)
        }
        return count
    }

    private func saveMetadata(modName: String, modId: Int?, to folder: URL) {
        let metadata = ModMetadata(
            gameBananaName: modName,
            gameBananaModId: modId,
            downloadedAt: Date()
        )
        do {
            try metadata.save(to: folder)
            print("[DownloadManager] Saved metadata to: \(folder.path)")
        } catch {
            print("[DownloadManager] Failed to save metadata: \(error)")
        }
    }

    private func extractAndInstallMods(from archiveURL: URL, to modFolder: URL) async throws -> Int {
        // Create temp extraction directory
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("extract_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: extractDir)
        }

        // Detect archive type and extract accordingly
        let lowercasedFilename = archiveURL.lastPathComponent.lowercased()

        if lowercasedFilename.hasSuffix(".7z") {
            // Use 7-Zip for .7z files
            try await extract7z(from: archiveURL, to: extractDir)
        } else if lowercasedFilename.hasSuffix(".rar") {
            // For RAR files, try 7-Zip first, fall back to unrar
            try await extractRar(from: archiveURL, to: extractDir)
        } else {
            // Use ditto for ZIP and other formats
            try await extractZip(from: archiveURL, to: extractDir)
        }

        // Security: Validate no zip slip - all extracted files must be within extractDir
        try validateExtractedFiles(in: extractDir)

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

    /// Extract a ZIP archive using ditto
    private func extractZip(from archiveURL: URL, to extractDir: URL) async throws {
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
    }

    /// Extract a 7z archive using 7-Zip
    private func extract7z(from archiveURL: URL, to extractDir: URL) async throws {
        guard let sevenZipPath = find7zBinary() else {
            throw DownloadError.sevenZipNotFound
        }


        let process = Process()
        process.executableURL = URL(fileURLWithPath: sevenZipPath)
        // x = extract with full paths, -o = output directory, -y = yes to all prompts
        process.arguments = ["x", archiveURL.path, "-o\(extractDir.path)", "-y"]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw DownloadError.extractionFailed
        }
    }

    /// Extract a RAR archive - tries 7-Zip first, falls back to unrar
    private func extractRar(from archiveURL: URL, to extractDir: URL) async throws {
        // Try 7-Zip first (handles most RAR files)
        if let sevenZipPath = find7zBinary() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: sevenZipPath)
            process.arguments = ["x", archiveURL.path, "-o\(extractDir.path)", "-y"]

            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = pipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return
            }

            // 7-Zip failed, check if it's an unsupported method error
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? ""

            // Only fall through to unar if it's an unsupported compression method
            // For other errors (corrupt file, etc.), throw immediately
            if !errorString.contains("Unsupported Method") {
                throw DownloadError.extractionFailed
            }
            // Fall through to unar fallback below
        }

        // Try unar as fallback (or primary if 7-Zip not available)
        guard let unarPath = findUnarBinary() else {
            // If 7-Zip is available but failed, and unar isn't available
            if find7zBinary() != nil {
                throw DownloadError.rarMethodUnsupported
            } else {
                throw DownloadError.sevenZipNotFound
            }
        }


        let process = Process()
        process.executableURL = URL(fileURLWithPath: unarPath)
        // -o = output directory, -f = force overwrite
        process.arguments = ["-o", extractDir.path, "-f", archiveURL.path]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw DownloadError.extractionFailed
        }
    }

    /// Find unar binary - checks common Homebrew paths
    private func findUnarBinary() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/unar",        // Homebrew on Apple Silicon
            "/usr/local/bin/unar",           // Homebrew on Intel
            "/opt/local/bin/unar"            // MacPorts
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Check if unar is available on the system
    func isUnarAvailable() -> Bool {
        return findUnarBinary() != nil
    }

    /// Find 7-Zip binary - checks bundled, then common Homebrew paths
    private func find7zBinary() -> String? {

        // Check if bundled with app
        if let bundledPath = Bundle.main.path(forResource: "7zz", ofType: nil) {
            if FileManager.default.isExecutableFile(atPath: bundledPath) {
                return bundledPath
            }
        }

        // Check common Homebrew/MacPorts paths
        let possiblePaths = [
            "/opt/homebrew/bin/7z",          // Homebrew on Apple Silicon
            "/opt/homebrew/bin/7zz",         // 7-Zip official binary
            "/usr/local/bin/7z",             // Homebrew on Intel
            "/usr/local/bin/7zz",            // 7-Zip official binary
            "/opt/local/bin/7z",             // MacPorts
            "/opt/local/bin/7zz"             // MacPorts
        ]

        for path in possiblePaths {
            let exists = FileManager.default.isExecutableFile(atPath: path)
            if exists {
                return path
            }
        }

        return nil
    }

    /// Check if 7-Zip is available on the system
    func is7zAvailable() -> Bool {
        return find7zBinary() != nil
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

    /// Sanitize folder name for filesystem using allowlist approach
    private func sanitizeFolderName(_ name: String) -> String {
        // Normalize unicode to prevent bypass attacks
        let normalized = name.precomposedStringWithCanonicalMapping

        // Allowlist: only keep alphanumeric, hyphen, underscore, space, and common safe chars
        let allowedCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_ .()[]"))

        var sanitized = String(normalized.unicodeScalars.filter { allowedCharacters.contains($0) })

        // Remove leading/trailing dots and spaces (prevent hidden files, trailing issues)
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        // Collapse multiple spaces into one
        while sanitized.contains("  ") {
            sanitized = sanitized.replacingOccurrences(of: "  ", with: " ")
        }

        // Limit length
        if sanitized.count > 50 {
            sanitized = String(sanitized.prefix(50)).trimmingCharacters(in: .whitespaces)
        }

        return sanitized.isEmpty ? "mod" : sanitized
    }

    /// Security: Validate that all extracted files are within the expected directory (zip slip protection)
    private func validateExtractedFiles(in directory: URL) throws {
        let directoryPath = directory.standardizedFileURL.path

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            // Resolve the real path to catch symlink attacks
            let resolvedURL = fileURL.resolvingSymlinksInPath()
            let resolvedPath = resolvedURL.standardizedFileURL.path

            // Verify the file is within the extraction directory
            if !resolvedPath.hasPrefix(directoryPath) {
                print("[DownloadManager] Security: Zip slip detected! File escapes directory: \(resolvedPath)")
                throw DownloadError.zipSlipDetected
            }

            // Check for symlinks pointing outside the directory
            var isSymlink: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isSymlink) {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
                if resourceValues?.isSymbolicLink == true {
                    let linkDest = try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path)
                    if let dest = linkDest {
                        let absoluteDest = directory.appendingPathComponent(dest).resolvingSymlinksInPath().path
                        if !absoluteDest.hasPrefix(directoryPath) {
                            print("[DownloadManager] Security: Symlink escape detected: \(fileURL.path) -> \(dest)")
                            throw DownloadError.zipSlipDetected
                        }
                    }
                }
            }
        }
    }

    private func updateDownloadStatus(fileId: Int, status: Download.DownloadStatus, message: String? = nil) {
        if let index = downloads.firstIndex(where: { $0.fileId == fileId }) {
            downloads[index].status = status
            if let message = message {
                downloads[index].statusMessage = message
            }
        }
        if currentDownload?.fileId == fileId {
            currentDownload?.status = status
            if let message = message {
                currentDownload?.statusMessage = message
            }
        }
    }

    private func updateDownloadProgress(fileId: Int, totalBytes: Int64, downloadedBytes: Int64) {
        let progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0
        if let index = downloads.firstIndex(where: { $0.fileId == fileId }) {
            downloads[index].progress = progress
            downloads[index].totalBytes = totalBytes
            downloads[index].downloadedBytes = downloadedBytes
        }
        if currentDownload?.fileId == fileId {
            currentDownload?.progress = progress
            currentDownload?.totalBytes = totalBytes
            currentDownload?.downloadedBytes = downloadedBytes
        }
    }

    private func showResult(success: Bool, message: String) {
        onDownloadComplete?(success, message)
    }

    /// Download file using URLSessionDownloadTask for browser-equivalent speed
    /// This method uses delegate-based downloading instead of byte-by-byte streaming
    private func downloadWithProgress(url: URL, filename: String, fileId: Int) async throws -> URL {
        // Create a dedicated delegate instance for this download
        let delegate = DownloadDelegate()

        // Create session with delegate
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300 // 5 minutes
        config.httpAdditionalHeaders = ["User-Agent": "Sailswift/1.0"]
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        // Use withCheckedThrowingContinuation to bridge delegate callbacks to async/await
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            delegate.onProgress = { [weak self] totalBytesWritten, totalBytesExpectedToWrite in
                Task { @MainActor in
                    self?.updateDownloadProgress(
                        fileId: fileId,
                        totalBytes: totalBytesExpectedToWrite,
                        downloadedBytes: totalBytesWritten
                    )
                }
            }

            delegate.onComplete = { [weak self] location, error in
                guard !hasResumed else { return }
                hasResumed = true

                // Invalidate session to break retain cycle and release resources
                session.finishTasksAndInvalidate()

                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let location = location else {
                    continuation.resume(throwing: DownloadError.downloadFailed)
                    return
                }

                // Move downloaded file to a stable temp location before the delegate cleans it up
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sailswift_\(UUID().uuidString)")
                let tempFile = tempDir.appendingPathComponent(filename)

                do {
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: location, to: tempFile)
                    continuation.resume(returning: tempFile)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            let task = session.downloadTask(with: url)
            task.resume()
        }
    }
}

enum DownloadError: LocalizedError {
    case downloadFailed
    case extractionFailed
    case sevenZipNotFound
    case rarMethodUnsupported
    case checksumMismatch
    case zipSlipDetected

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "Download failed - no file received"
        case .extractionFailed: return "Failed to extract archive"
        case .sevenZipNotFound: return "7-Zip is required to extract .7z and .rar files. Install via: brew install 7zip"
        case .rarMethodUnsupported: return "This RAR file uses a compression method not supported by 7-Zip. Install unar via: brew install unar"
        case .checksumMismatch: return "Download verification failed - file may be corrupted or tampered"
        case .zipSlipDetected: return "Security error: Archive contains unsafe file paths"
        }
    }
}
