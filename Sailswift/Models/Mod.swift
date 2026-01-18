import Foundation

/// Represents a mod file in the mods directory
struct Mod: Identifiable, Hashable {
    let id: String
    let name: String
    let path: URL
    let isEnabled: Bool
    let fileExtension: ModFileExtension
    let relativePath: String

    /// The folder path relative to the mods directory (empty string if at root)
    var folderPath: String {
        let components = relativePath.components(separatedBy: "/")
        if components.count > 1 {
            return components.dropLast().joined(separator: "/")
        }
        return ""
    }

    init(path: URL, relativePath: String) {
        self.path = path
        self.relativePath = relativePath

        let ext = path.pathExtension.lowercased()

        // Determine file extension type
        self.fileExtension = ModFileExtension(rawValue: ext) ?? .otr

        // Determine enabled state based on extension
        self.isEnabled = (ext == "otr" || ext == "o2r")

        // Extract name without extension
        self.name = path.deletingPathExtension().lastPathComponent

        // Use relative path as ID for uniqueness
        self.id = relativePath
    }

    /// Get the path for the toggled state
    func toggledPath() -> URL {
        let newExtension: String
        switch fileExtension {
        case .otr:
            newExtension = "disabled"
        case .o2r:
            newExtension = "di2abled"
        case .disabled:
            newExtension = "otr"
        case .di2abled:
            newExtension = "o2r"
        }
        return path.deletingPathExtension().appendingPathExtension(newExtension)
    }
}

/// Supported mod file extensions
enum ModFileExtension: String, CaseIterable {
    case otr = "otr"
    case o2r = "o2r"
    case disabled = "disabled"
    case di2abled = "di2abled"

    var isEnabled: Bool {
        switch self {
        case .otr, .o2r:
            return true
        case .disabled, .di2abled:
            return false
        }
    }

    static var enabledExtensions: [String] {
        ["otr", "o2r"]
    }

    static var disabledExtensions: [String] {
        ["disabled", "di2abled"]
    }

    static var allExtensions: [String] {
        enabledExtensions + disabledExtensions
    }
}

/// Represents a folder in the mod tree
struct ModFolder: Identifiable, Hashable {
    let id: String
    let name: String
    let path: URL
    let relativePath: String
    var state: ModFolderState = .empty

    init(path: URL, relativePath: String) {
        self.path = path
        self.relativePath = relativePath
        self.name = path.lastPathComponent
        self.id = relativePath
    }
}

/// State of mods within a folder
enum ModFolderState: Hashable {
    case allEnabled
    case allDisabled
    case mixed
    case empty

    var iconName: String {
        switch self {
        case .allEnabled: return "checkmark.circle.fill"
        case .allDisabled: return "xmark.circle.fill"
        case .mixed: return "minus.circle.fill"
        case .empty: return "folder"
        }
    }
}

/// A node in the mod tree (either a folder or a mod)
enum ModTreeNode: Identifiable, Hashable {
    case folder(ModFolder, children: [ModTreeNode])
    case mod(Mod)

    var id: String {
        switch self {
        case .folder(let folder, _): return "folder:\(folder.id)"
        case .mod(let mod): return "mod:\(mod.id)"
        }
    }

    var name: String {
        switch self {
        case .folder(let folder, _): return folder.name
        case .mod(let mod): return mod.name
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}
