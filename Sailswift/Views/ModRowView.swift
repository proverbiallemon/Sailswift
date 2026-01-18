import SwiftUI

/// View for a single mod row in the tree
struct ModRowView: View {
    let mod: Mod
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
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
