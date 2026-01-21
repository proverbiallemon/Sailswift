import SwiftUI
import UniformTypeIdentifiers

/// View for exporting a modpack
struct ModpackExportView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var packName: String = ""
    @State private var packAuthor: String = ""
    @State private var packDescription: String = ""
    @State private var showingSavePanel = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("Export Modpack")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Divider()

            // Form
            Form {
                Section {
                    TextField("Pack Name", text: $packName)
                    TextField("Author", text: $packAuthor)
                    TextField("Description", text: $packDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        // Count unique folders (what actually gets exported)
                        let folderCount = countUniqueFolders()
                        let foldersWithIds = countFoldersWithGameBananaIds()

                        HStack {
                            Text("Mod folders to include:")
                                .font(.headline)
                            Spacer()
                            Text("\(folderCount)")
                                .foregroundColor(.secondary)
                        }

                        // Warning for folders without GameBanana IDs
                        let foldersWithoutIds = folderCount - foldersWithIds
                        if foldersWithoutIds > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("\(foldersWithoutIds) folder\(foldersWithoutIds == 1 ? "" : "s") without GameBanana IDs won't be downloadable by others")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("Load order and enabled states will be preserved.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Export...") {
                    showingSavePanel = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(packName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 450, height: 400)
        .fileExporter(
            isPresented: $showingSavePanel,
            document: ModpackDocument(modpack: createModpack()),
            contentType: .modpack,
            defaultFilename: packName.isEmpty ? "modpack" : packName
        ) { result in
            switch result {
            case .success(let url):
                appState.statusMessage = "Modpack exported to \(url.lastPathComponent)"
                dismiss()
            case .failure(let error):
                appState.statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func createModpack() -> Modpack {
        appState.createModpack(
            name: packName,
            author: packAuthor,
            description: packDescription
        )
    }

    /// Count unique top-level folders (what actually gets exported in a modpack)
    private func countUniqueFolders() -> Int {
        var seenFolders = Set<String>()
        for mod in appState.mods {
            let folderName = mod.folderPath.isEmpty ? mod.name : mod.folderPath.components(separatedBy: "/").first ?? mod.name
            seenFolders.insert(folderName)
        }
        return seenFolders.count
    }

    /// Count folders that have GameBanana metadata (can be auto-downloaded)
    private func countFoldersWithGameBananaIds() -> Int {
        var count = 0
        var seenFolders = Set<String>()

        for mod in appState.mods {
            let folderName = mod.folderPath.isEmpty ? mod.name : mod.folderPath.components(separatedBy: "/").first ?? mod.name
            if seenFolders.contains(folderName) { continue }
            seenFolders.insert(folderName)

            if !mod.folderPath.isEmpty {
                let topLevelFolder = mod.folderPath.components(separatedBy: "/").first ?? mod.folderPath
                let folderURL = appState.modsDirectory.appendingPathComponent(topLevelFolder)
                if let metadata = ModMetadata.load(from: folderURL), metadata.gameBananaModId != nil {
                    count += 1
                }
            }
        }
        return count
    }
}

/// Document type for modpack files
struct ModpackDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.modpack] }

    let modpack: Modpack

    init(modpack: Modpack) {
        self.modpack = modpack
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        modpack = try decoder.decode(Modpack.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(modpack)
        return FileWrapper(regularFileWithContents: data)
    }
}

/// UTType extension for modpack files
extension UTType {
    static let modpack = UTType(exportedAs: "com.proverbiallemon.sailswift.modpack", conformingTo: .json)
}
