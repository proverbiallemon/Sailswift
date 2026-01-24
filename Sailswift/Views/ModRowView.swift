import SwiftUI
import Pow

/// View for a single mod row in the tree
struct ModRowView: View {
    @EnvironmentObject var appState: AppState
    let mod: Mod
    let onToggle: () -> Void
    var loadOrderIndex: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            // Load order number for enabled mods
            if let index = loadOrderIndex {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 20, alignment: .trailing)
            }

            // Clickable toggle button (disabled in multi-select mode)
            Button(action: onToggle) {
                Image(systemName: mod.isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(appState.isInMultiSelectMode ? .secondary : (mod.isEnabled ? .green : .red))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .disabled(appState.isInMultiSelectMode)
            .help(appState.isInMultiSelectMode ? "Exit multi-select mode to toggle" : (mod.isEnabled ? "Disable mod" : "Enable mod"))

            Image(systemName: "doc.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            Text(mod.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
    }
}

/// View for a mod in the load order list with up/down reorder controls
struct LoadOrderRowView: View {
    let modName: String
    let index: Int
    let totalCount: Int
    let onToggle: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Load order number
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .trailing)

            // Disable button
            Button(action: onToggle) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Disable mod")

            // Vertical reorder control - stacked up/down buttons
            VStack(spacing: 0) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(index > 0 ? .secondary : .secondary.opacity(0.3))
                .disabled(index == 0)
                .help("Move up (higher priority)")

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(index < totalCount - 1 ? .secondary : .secondary.opacity(0.3))
                .disabled(index >= totalCount - 1)
                .help("Move down (lower priority)")
            }
            .frame(width: 16)

            Text(modName)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
    }
}

/// View for a folder row in the tree
struct FolderRowView: View {
    @EnvironmentObject var appState: AppState
    let folder: ModFolder
    let onToggle: () -> Void
    var hasUpdate: Bool = false

    @State private var shineToggle = false

    private var isSelected: Bool {
        appState.isFolderSelected(folder.relativePath)
    }

    private var isPendingDeletion: Bool {
        appState.pendingDeletion?.folderPaths.contains(folder.relativePath) ?? false
    }

    var body: some View {
        HStack(spacing: 8) {
            // Selection checkbox (visible in multi-select mode or when pending deletion)
            if appState.isInMultiSelectMode || appState.pendingDeletion != nil {
                Button {
                    appState.toggleFolderSelection(folder.relativePath)
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .secondary.opacity(0.5))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }

            // Clickable toggle button (disabled in multi-select mode)
            Button(action: onToggle) {
                Image(systemName: folder.state.iconName)
                    .foregroundColor(appState.isInMultiSelectMode ? .secondary : colorForState(folder.state))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .disabled(appState.isInMultiSelectMode)
            .help(appState.isInMultiSelectMode ? "Exit multi-select mode to toggle" : "Toggle all mods in folder")

            ZStack(alignment: .topTrailing) {
                Image(systemName: "folder.fill")
                    .foregroundColor(isPendingDeletion ? .gray : .blue)
                    .font(.system(size: 12))

                // Update available badge
                if hasUpdate && !isPendingDeletion {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: 3, y: -2)
                }
            }

            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(isPendingDeletion ? .secondary : .primary)

            // Update indicator button with shine effect
            if hasUpdate && !isPendingDeletion {
                Button {
                    Task { await appState.updateMod(folderPath: folder.relativePath) }
                } label: {
                    Text("Update")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.orange))
                        .changeEffect(.shine, value: shineToggle)
                }
                .buttonStyle(.plain)
                .help("Click to update this mod")
                .onAppear {
                    // Start repeating shine animation
                    startShineTimer()
                }
            }

            Spacer()
        }
        .opacity(isPendingDeletion ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .contextMenu {
            if hasUpdate {
                Button("Update Mod") {
                    Task { await appState.updateMod(folderPath: folder.relativePath) }
                }
            }
            Button("Show in Finder") {
                FileService.shared.openInFinder(folder.path)
            }
        }
        .simultaneousGesture(
            TapGesture().modifiers(.command).onEnded {
                // Command+click - toggle selection (also enters multi-select implicitly)
                appState.toggleFolderSelection(folder.relativePath)
            }
        )
    }

    private func startShineTimer() {
        // Shine every 3 seconds
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                shineToggle.toggle()
            }
        }
    }

    private func colorForState(_ state: ModFolderState) -> Color {
        if isPendingDeletion { return .gray }
        switch state {
        case .allEnabled: return .green
        case .allDisabled: return .red
        case .mixed: return .orange
        case .empty: return .gray
        }
    }
}
