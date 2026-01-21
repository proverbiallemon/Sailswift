import SwiftUI
import Marquee
import Pow

/// Scrolling ticker notification bar - classic news ticker style (right to left)
struct NotificationTickerView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentIndex: Int = 0

    private var currentMessage: NotificationMessage? {
        guard !appState.notifications.isEmpty else { return nil }
        let safeIndex = abs(currentIndex) % max(1, appState.notifications.count)
        return appState.notifications[safeIndex]
    }

    var body: some View {
        Button {
            appState.showNotificationPopover = true
        } label: {
            HStack(spacing: 0) {
                // Scrolling text area using Marquee library
                if let message = currentMessage {
                    Marquee {
                        Text(message.text)
                            .font(.system(size: 11))
                            .foregroundColor(message.type.color)
                    }
                    .marqueeDirection(.right2left)
                    .marqueeDuration(max(6.0, Double(message.text.count) * 0.2)) // Slower scroll, min 6 sec
                    .marqueeWhenNotFit(false) // Always scroll
                    .marqueeIdleAlignment(.leading)
                    .marqueeAutoreverses(false)
                    .id(message.id)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No notifications")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 4)

                // Notification count badge
                if appState.notifications.count > 0 {
                    Text("\(appState.notifications.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.6)))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: 22)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .contentShape(Rectangle())
        .popover(isPresented: $appState.showNotificationPopover, arrowEdge: .bottom) {
            NotificationLogPopover()
                .environmentObject(appState)
        }
        .onChange(of: appState.notifications.count) { _ in
            currentIndex = 0
        }
        .onReceive(Timer.publish(every: 12, on: .main, in: .common).autoconnect()) { _ in
            // Cycle through notifications every 12 seconds (allows 2 full loops)
            if appState.notifications.count > 1 {
                withAnimation {
                    currentIndex = (currentIndex + 1) % appState.notifications.count
                }
            }
        }
    }
}

/// Red confirmation ticker for destructive actions
struct ConfirmationTickerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let pending = appState.pendingDeletion {
            Button {
                appState.showDeleteConfirmPopover = true
            } label: {
                HStack(spacing: 0) {
                    // Static confirmation text
                    Text(pending.tickerText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 4)

                    // Cancel X button
                    Button {
                        appState.cancelPendingDeletion()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .buttonStyle(.plain)
            .frame(height: 22)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.85))
            .contentShape(Rectangle())
            .popover(isPresented: $appState.showDeleteConfirmPopover, arrowEdge: .bottom) {
                DeleteConfirmPopover()
                    .environmentObject(appState)
            }
        }
    }
}

/// Popover to confirm deletion
struct DeleteConfirmPopover: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.red)

            // Confirmation text
            if let pending = appState.pendingDeletion {
                Text(pending.confirmationText)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if pending.folderPaths.count > 1 {
                    Text("This will permanently delete \(pending.modCount) mod files.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    appState.cancelPendingDeletion()
                }
                .keyboardShortcut(.escape)

                Button("Delete") {
                    Task {
                        await appState.confirmPendingDeletion()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}

/// Popover showing all notification messages
struct NotificationLogPopover: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Notifications")
                    .font(.headline)
                Spacer()
                if !appState.notifications.isEmpty {
                    Button("Clear All") {
                        appState.clearAllNotifications()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Modpack to Profile prompt (if pending)
            if let modpack = appState.pendingModpackProfile {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundColor(.purple)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save as Profile?")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Create a profile from '\(modpack.name)'")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        Button("No Thanks") {
                            appState.dismissModpackProfilePrompt()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Create Profile") {
                            appState.createProfileFromModpack()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Divider()
                    .padding(.top, 8)
            }

            // Messages list
            if appState.notifications.isEmpty {
                Text("No notifications")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.notifications) { notification in
                            NotificationRowView(notification: notification) {
                                appState.clearNotification(notification)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 320)
    }
}

/// Single notification row in the popover
struct NotificationRowView: View {
    let notification: NotificationMessage
    let onDismiss: () -> Void

    @State private var isHovering = false

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(notification.timestamp)
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }

    var body: some View {
        Button(action: onDismiss) {
            HStack(alignment: .top, spacing: 8) {
                // Type indicator
                Circle()
                    .fill(notification.type.color)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)

                // Message content
                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.text)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(timeAgo)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// View displaying the mod tree in the sidebar
struct ModListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedNode: ModTreeNode?
    @Binding var searchText: String

    @State private var modTree: [ModTreeNode] = []
    @State private var expandedFolders: Set<String> = []
    @State private var loadOrderExpanded: Bool = false
    @State private var profilesExpanded: Bool = false
    @State private var showSaveProfileAlert: Bool = false
    @State private var newProfileName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Notification ticker (above mods section)
            NotificationTickerView()

            // Confirmation ticker (red, for destructive actions)
            ConfirmationTickerView()

            // Main mods tree list
            List(selection: $selectedNode) {
                Section {
                    // Profile downloads in progress (shown as placeholders)
                    ForEach(appState.profileDownloads) { download in
                        ProfileDownloadPlaceholderView(download: download)
                    }

                    // Regular mod tree
                    ForEach(filteredModTree) { node in
                        ModTreeNodeView(
                            node: node,
                            expandedFolders: $expandedFolders,
                            onToggle: { toggleNode($0) },
                            loadOrderIndexProvider: { appState.loadOrderIndex(for: $0) },
                            updateCheckProvider: { appState.hasModUpdate(for: $0) }
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

            // Action bar for quick mod operations
            modActionBar

            // Profiles section
            Divider()
            profilesSection

            // Load Order section (separate list for drag-drop support)
            if !appState.modLoadOrder.isEmpty {
                Divider()
                loadOrderSection
            }
        }
        .task { await buildModTree() }
        .onChange(of: appState.mods) { _ in Task { await buildModTree() } }
        .onDeleteCommand {
            // Delete key pressed - trigger deletion of selected folders
            if !appState.selectedFolders.isEmpty {
                appState.requestDeleteSelectedFolders()
            }
        }
        .alert("Save Profile", isPresented: $showSaveProfileAlert) {
            TextField("Profile Name", text: $newProfileName)
            Button("Cancel", role: .cancel) {
                newProfileName = ""
            }
            Button("Save") {
                if !newProfileName.isEmpty {
                    appState.saveProfile(name: newProfileName)
                    newProfileName = ""
                }
            }
        } message: {
            Text("Enter a name for this profile")
        }
    }

    /// Bottom action bar for quick mod operations
    @ViewBuilder
    private var modActionBar: some View {
        HStack(spacing: 12) {
            // Multi-select mode toggle
            Button {
                appState.toggleMultiSelectMode()
            } label: {
                Image(systemName: appState.isInMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundColor(appState.isInMultiSelectMode ? .blue : .secondary)
            .help(appState.isInMultiSelectMode ? "Exit multi-select mode" : "Enter multi-select mode")

            // Toggle button (disabled during multi-select)
            Button {
                if let node = selectedNode {
                    toggleNode(node)
                }
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .disabled(selectedNode == nil || appState.isInMultiSelectMode)
            .help("Toggle selected mod/folder")

            // Delete button
            Button {
                deleteSelectedItem()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(selectedNode == nil && appState.selectedFolders.isEmpty)
            .help("Delete selected")

            Spacer()

            // Selection count (when in multi-select mode)
            if appState.isInMultiSelectMode && !appState.selectedFolders.isEmpty {
                Text("\(appState.selectedFolders.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Open mods folder button
            Button {
                FileService.shared.openInFinder(appState.modsDirectory)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open mods folder")

            // Refresh button
            Button {
                Task { await appState.loadMods() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh mod list")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    /// Delete the currently selected item (node or multi-selected folders)
    private func deleteSelectedItem() {
        // If there are multi-selected folders, use batch delete
        if !appState.selectedFolders.isEmpty {
            appState.requestDeleteSelectedFolders()
            return
        }

        // Otherwise delete the single selected node
        guard let node = selectedNode else { return }
        Task {
            switch node {
            case .mod(let mod):
                await appState.deleteMod(mod)
            case .folder(let folder, _):
                await appState.deleteFolder(folder.path)
            }
            selectedNode = nil
        }
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

    @ViewBuilder
    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (clickable to expand/collapse)
            Button {
                withAnimation { profilesExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: profilesExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.purple)
                    Text("Profiles").fontWeight(.semibold)
                    Spacer()
                    Text("\(appState.profileManager.profiles.count)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if profilesExpanded {
                VStack(spacing: 4) {
                    // Save current state button
                    Button {
                        showSaveProfileAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Save Current State")
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)

                    // Saved profiles list
                    if appState.profileManager.profiles.isEmpty {
                        Text("No saved profiles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(appState.profileManager.profiles) { profile in
                            ProfileRowView(
                                profile: profile,
                                isActive: appState.profileManager.activeProfileId == profile.id,
                                onApply: {
                                    Task { await appState.applyProfile(profile) }
                                },
                                onUpdate: {
                                    appState.updateProfile(profile)
                                },
                                onDelete: {
                                    appState.deleteProfile(profile)
                                }
                            )
                        }
                    }
                }
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
    var updateCheckProvider: ((String) -> Bool)? = nil

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
                    ModTreeNodeView(
                        node: child,
                        expandedFolders: $expandedFolders,
                        onToggle: onToggle,
                        loadOrderIndexProvider: loadOrderIndexProvider,
                        updateCheckProvider: updateCheckProvider
                    )
                }
            } label: {
                FolderRowView(
                    folder: folder,
                    onToggle: { onToggle(node) },
                    hasUpdate: updateCheckProvider?(folder.relativePath) ?? false
                )
            }
            .tag(node)
        }
    }
}

/// Placeholder row showing a mod being downloaded from a profile
struct ProfileDownloadPlaceholderView: View {
    let download: ProfileDownloadProgress

    @State private var effectTrigger = 0

    var body: some View {
        HStack(spacing: 8) {
            // Status icon with animations
            statusIcon
                .changeEffect(
                    .spray(origin: UnitPoint(x: 0.5, y: 0.5)) {
                        Image(systemName: "sparkle")
                            .foregroundStyle(.green)
                    },
                    value: effectTrigger,
                    isEnabled: download.status == .completed
                )
                .changeEffect(
                    .shake(rate: .fast),
                    value: effectTrigger,
                    isEnabled: download.status == .failed
                )

            // Mod info and progress
            VStack(alignment: .leading, spacing: 4) {
                Text(download.folderName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)

                        // Progress fill
                        RoundedRectangle(cornerRadius: 2)
                            .fill(download.status == .extracting ? Color.orange : Color.blue)
                            .frame(width: geometry.size.width * download.progress, height: 4)
                            .animation(.linear(duration: 0.1), value: download.progress)
                    }
                }
                .frame(height: 4)

                // Status text
                Text(download.progressText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
        // Poof! Cartoon cloud when dismissing
        .transition(.movingParts.poof)
        .onChange(of: download.status) { newStatus in
            if newStatus == .completed || newStatus == .failed {
                effectTrigger += 1
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if download.status == .completed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else if download.status == .failed {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
        } else {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        }
    }
}

/// Row displaying a saved profile with actions
struct ProfileRowView: View {
    let profile: ModProfile
    let isActive: Bool
    let onApply: () -> Void
    let onUpdate: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 8) {
            // Active indicator
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }

            // Profile info
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)
                Text("\(profile.enabledCount)/\(profile.totalCount) enabled")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action buttons (show on hover)
            if isHovering {
                HStack(spacing: 4) {
                    Button(action: onApply) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("Apply: Enable/disable mods to match this profile")

                    Button(action: onUpdate) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.borderless)
                    .help("Save: Overwrite this profile with current mod state")

                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this profile")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.green.opacity(0.1) : (isHovering ? Color.secondary.opacity(0.1) : Color.clear))
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .onHover { isHovering = $0 }
        .confirmationDialog("Delete Profile", isPresented: $showDeleteConfirm) {
            Button("Delete \"\(profile.name)\"", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this profile?")
        }
    }
}
