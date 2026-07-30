import Foundation

/// Validates archive entry paths before extraction so path-traversal entries
/// are rejected before any file is written to disk. The post-extraction
/// symlink check in DownloadManager remains as a second layer.
enum ArchiveEntryValidator {
    enum ValidationError: Error, Equatable {
        case pathTraversal(String)
        case absolutePath(String)
    }

    /// Reject entries with absolute paths or `..` path components.
    /// Splits on both `/` and `\` so Windows-built archives are covered.
    static func validate(entries: [String]) throws {
        for entry in entries {
            if entry.hasPrefix("/") {
                throw ValidationError.absolutePath(entry)
            }
            let components = entry.split(whereSeparator: { $0 == "/" || $0 == "\\" })
            if components.contains("..") {
                throw ValidationError.pathTraversal(entry)
            }
        }
    }
}
