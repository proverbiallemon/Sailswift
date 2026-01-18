import Foundation

/// Manager for mod operations
@MainActor
class ModManager: ObservableObject {
    private let fileService = FileService.shared

    /// Load all mods from the mods directory
    func loadMods(from directory: URL) async throws -> [Mod] {
        let modFiles = try fileService.listModFiles(in: directory)
        return modFiles.map { url in
            let relativePath = fileService.relativePath(of: url, from: directory)
            return Mod(path: url, relativePath: relativePath)
        }.sorted { $0.relativePath < $1.relativePath }
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
