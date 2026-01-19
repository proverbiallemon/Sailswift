import SwiftUI

/// View displaying the mod tree in the sidebar
struct ModListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedNode: ModTreeNode?
    @Binding var searchText: String

    @State private var modTree: [ModTreeNode] = []
    @State private var expandedFolders: Set<String> = []
    @State private var loadOrderExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Main mods tree list
            List(selection: $selectedNode) {
                Section {
                    ForEach(filteredModTree) { node in
                        ModTreeNodeView(
                            node: node,
                            expandedFolders: $expandedFolders,
                            onToggle: { toggleNode($0) },
                            loadOrderIndexProvider: { appState.loadOrderIndex(for: $0) }
                        )
                    }
                } header: {
                    HStack {
                        Image(systemName: rootFolderIcon).foregroundColor(rootFolderColor)
                        Text("mods").fontWeight(.semibold)
                        Spacer()
                        Text("\(appState.mods.count)").foregroundColor(.secondary).font(.caption)
                    }
                }
            }
            .listStyle(.sidebar)

            // Load Order section (separate list for drag-drop support)
            if !appState.modLoadOrder.isEmpty {
                Divider()
                loadOrderSection
            }
        }
        .task { await buildModTree() }
        .onChange(of: appState.mods) { _ in Task { await buildModTree() } }
    }

    @ViewBuilder
    private var loadOrderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (clickable to expand/collapse)
            Button {
                withAnimation { loadOrderExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: loadOrderExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text("Load Order").fontWeight(.semibold)
                    Spacer()
                    Text("\(appState.modLoadOrder.count)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if loadOrderExpanded {
                // Reorderable list with onMove
                List {
                    ForEach(appState.modLoadOrder, id: \.self) { modName in
                        LoadOrderRowView(
                            modName: modName,
                            index: appState.modLoadOrder.firstIndex(of: modName) ?? 0,
                            totalCount: appState.modLoadOrder.count,
                            onToggle: {
                                if let mod = appState.mods.first(where: { $0.name == modName }) {
                                    Task { await appState.toggleMod(mod) }
                                }
                            },
                            onMoveUp: { appState.moveModUp(modName) },
                            onMoveDown: { appState.moveModDown(modName) }
                        )
                    }
                    .onMove { indices, newOffset in
                        appState.modLoadOrder.move(fromOffsets: indices, toOffset: newOffset)
                        appState.syncLoadOrderToConfig()
                    }
                }
                .listStyle(.inset)
                .frame(maxHeight: 200)

                Text("Higher position = Higher priority (loads last)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var filteredModTree: [ModTreeNode] {
        if searchText.isEmpty { return modTree }
        return filterTree(modTree, searchText: searchText.lowercased())
    }

    private var rootFolderState: ModFolderState {
        if appState.mods.isEmpty { return .empty }
        let enabledCount = appState.mods.filter { $0.isEnabled }.count
        if enabledCount == appState.mods.count { return .allEnabled }
        if enabledCount == 0 { return .allDisabled }
        return .mixed
    }

    private var rootFolderIcon: String { rootFolderState.iconName }

    private var rootFolderColor: Color {
        switch rootFolderState {
        case .allEnabled: return .green
        case .allDisabled: return .red
        case .mixed: return .orange
        case .empty: return .gray
        }
    }

    private func buildModTree() async {
        modTree = appState.modManager.buildModTree(from: appState.mods, baseDirectory: appState.modsDirectory)
    }

    private func filterTree(_ nodes: [ModTreeNode], searchText: String) -> [ModTreeNode] {
        var result: [(node: ModTreeNode, score: Int)] = []

        for node in nodes {
            switch node {
            case .mod(let mod):
                if let score = mod.name.fuzzyMatch(searchText) {
                    result.append((node, score))
                }
            case .folder(let folder, let children):
                let filteredChildren = filterTree(children, searchText: searchText)
                if !filteredChildren.isEmpty {
                    result.append((.folder(folder, children: filteredChildren), 0))
                } else if let score = folder.name.fuzzyMatch(searchText) {
                    result.append((.folder(folder, children: []), score))
                }
            }
        }

        // Sort by score (highest first), then by name
        return result
            .sorted { $0.score > $1.score }
            .map { $0.node }
    }

    private func toggleNode(_ node: ModTreeNode) {
        Task {
            switch node {
            case .mod(let mod): await appState.toggleMod(mod)
            case .folder(let folder, _): await appState.toggleFolder(folder.path)
            }
        }
    }
}

struct ModTreeNodeView: View {
    let node: ModTreeNode
    @Binding var expandedFolders: Set<String>
    let onToggle: (ModTreeNode) -> Void
    var loadOrderIndexProvider: ((String) -> Int?)? = nil

    var body: some View {
        switch node {
        case .mod(let mod):
            ModRowView(
                mod: mod,
                onToggle: { onToggle(node) },
                loadOrderIndex: mod.isEnabled ? loadOrderIndexProvider?(mod.name) : nil
            ).tag(node)
        case .folder(let folder, let children):
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedFolders.contains(folder.id) },
                    set: { if $0 { expandedFolders.insert(folder.id) } else { expandedFolders.remove(folder.id) } }
                )
            ) {
                ForEach(children) { child in
                    ModTreeNodeView(node: child, expandedFolders: $expandedFolders, onToggle: onToggle, loadOrderIndexProvider: loadOrderIndexProvider)
                }
            } label: {
                FolderRowView(folder: folder, onToggle: { onToggle(node) })
            }
            .tag(node)
        }
    }
}
