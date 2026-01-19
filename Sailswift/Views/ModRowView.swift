import SwiftUI

/// View for a single mod row in the tree
struct ModRowView: View {
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

            // Clickable toggle button
            Button(action: onToggle) {
                Image(systemName: mod.isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(mod.isEnabled ? .green : .red)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help(mod.isEnabled ? "Disable mod" : "Enable mod")

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
    let folder: ModFolder
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Clickable toggle button
            Button(action: onToggle) {
                Image(systemName: folder.state.iconName)
                    .foregroundColor(colorForState(folder.state))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Toggle all mods in folder")

            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
                .font(.system(size: 12))

            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
    }

    private func colorForState(_ state: ModFolderState) -> Color {
        switch state {
        case .allEnabled: return .green
        case .allDisabled: return .red
        case .mixed: return .orange
        case .empty: return .gray
        }
    }
}
