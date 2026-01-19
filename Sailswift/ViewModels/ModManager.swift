import Foundation

/// Manager for mod operations
@MainActor
class ModManager: ObservableObject {
    private let fileService = FileService.shared

    /// Load all mods from the mods directory
    /// - Parameters:
    ///   - directory: The mods directory to load from
    ///   - loadOrder: Optional array of mod names defining load priority (earlier = lower priority)
    func loadMods(from directory: URL, loadOrder: [String] = []) async throws -> [Mod] {
        let modFiles = try fileService.listModFiles(in: directory)
        let allMods = modFiles.map { url in
            let relativePath = fileService.relativePath(of: url, from: directory)
            return Mod(path: url, relativePath: relativePath)
        }

        // Separate enabled and disabled mods
        let enabledMods = allMods.filter { $0.isEnabled }
        let disabledMods = allMods.filter { !$0.isEnabled }

        // Sort enabled mods by load order (mods not in order go to end, alphabetically)
        let sortedEnabledMods = enabledMods.sorted { mod1, mod2 in
            let index1 = loadOrder.firstIndex(of: mod1.name)
            let index2 = loadOrder.firstIndex(of: mod2.name)

            switch (index1, index2) {
            case let (i1?, i2?):
                return i1 < i2
            case (nil, _?):
                return false // mod1 not in order, goes after mod2
            case (_?, nil):
                return true  // mod1 in order, goes before mod2
            case (nil, nil):
                return mod1.name.localizedCaseInsensitiveCompare(mod2.name) == .orderedAscending
            }
        }

        // Sort disabled mods alphabetically
        let sortedDisabledMods = disabledMods.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Combine: enabled mods first (in load order), then disabled mods (alphabetically)
        return sortedEnabledMods + sortedDisabledMods
    }

    /// Build a tree structure of mods and folders
    func buildModTree(from mods: [Mod], baseDirectory: URL) -> [ModTreeNode] {
        var rootNodes: [ModTreeNode] = []
        var folderMap: [String: ModFolder] = [:]
        var folderChildren: [String: [ModTreeNode]] = [:]

        // Collect all unique folder paths
        var allFolderPaths = Set<String>()
        for mod in mods {
            let components = mod.relativePath.components(separatedBy: "/")
            var currentPath = ""
            for (index, component) in components.enumerated() {
                if index < components.count - 1 {
                    if !currentPath.isEmpty { currentPath += "/" }
                    currentPath += component
                    allFolderPaths.insert(currentPath)
                }
            }
        }

        // Create folder objects
        for folderPath in allFolderPaths {
            let folderURL = baseDirectory.appendingPathComponent(folderPath)
            var folder = ModFolder(path: folderURL, relativePath: folderPath)
            folder.state = calculateFolderState(folderPath: folderPath, mods: mods)
            folderMap[folderPath] = folder
            folderChildren[folderPath] = []
        }

        // Organize mods into folders
        for mod in mods {
            let modNode = ModTreeNode.mod(mod)
            if mod.folderPath.isEmpty {
                rootNodes.append(modNode)
            } else {
                folderChildren[mod.folderPath, default: []].append(modNode)
            }
        }

        // Organize folders hierarchically
        for folderPath in allFolderPaths.sorted() {
            let components = folderPath.components(separatedBy: "/")
            if components.count == 1 {
                if let folder = folderMap[folderPath] {
                    let children = folderChildren[folderPath] ?? []
                    rootNodes.append(.folder(folder, children: children))
                }
            } else {
                let parentPath = components.dropLast().joined(separator: "/")
                if let folder = folderMap[folderPath] {
                    let children = folderChildren[folderPath] ?? []
                    let folderNode = ModTreeNode.folder(folder, children: children)
                    folderChildren[parentPath, default: []].append(folderNode)
                }
            }
        }

        return rootNodes.sorted { $0.name < $1.name }
    }

    private func calculateFolderState(folderPath: String, mods: [Mod]) -> ModFolderState {
        let modsInFolder = mods.filter { mod in
            mod.folderPath == folderPath || mod.folderPath.hasPrefix(folderPath + "/")
        }

        if modsInFolder.isEmpty { return .empty }

        let enabledCount = modsInFolder.filter { $0.isEnabled }.count
        if enabledCount == modsInFolder.count { return .allEnabled }
        if enabledCount == 0 { return .allDisabled }
        return .mixed
    }

    /// Toggle a mod's enabled/disabled state
    func toggleMod(_ mod: Mod) async throws {
        let newPath = mod.toggledPath()
        try fileService.renameFile(from: mod.path, to: newPath)
    }

    /// Toggle all mods in a folder
    func toggleModsInFolder(_ folderURL: URL) async throws {
        let modFiles = try fileService.listModFiles(in: folderURL)
        guard !modFiles.isEmpty else { throw ModManagerError.noModsInFolder }

        let hasDisabled = modFiles.contains { url in
            let ext = url.pathExtension.lowercased()
            return ext == "disabled" || ext == "di2abled"
        }

        for fileURL in modFiles {
            let ext = fileURL.pathExtension.lowercased()

            if hasDisabled {
                if ext == "disabled" || ext == "di2abled" {
                    let newExt = ext == "disabled" ? "otr" : "o2r"
                    let newURL = fileURL.deletingPathExtension().appendingPathExtension(newExt)
                    try fileService.renameFile(from: fileURL, to: newURL)
                }
            } else {
                if ext == "otr" || ext == "o2r" {
                    let newExt = ext == "otr" ? "disabled" : "di2abled"
                    let newURL = fileURL.deletingPathExtension().appendingPathExtension(newExt)
                    try fileService.renameFile(from: fileURL, to: newURL)
                }
            }
        }
    }

    /// Delete a mod
    func deleteMod(_ mod: Mod) async throws {
        try fileService.delete(at: mod.path)
    }
}

enum ModManagerError: LocalizedError {
    case noModsInFolder

    var errorDescription: String? {
        switch self {
        case .noModsInFolder: return "No mods found in folder"
        }
    }
}
