import SwiftUI

/// Reusable thumbnail view for GameBanana mods with appropriate placeholder icons
struct ModThumbnailView: View {
    let imageURL: URL?
    let itemType: String
    let size: ThumbnailSize

    enum ThumbnailSize {
        case small   // 60x45 - for import confirmation
        case medium  // 80x60 - for list rows
        case large   // full width, 150pt height - for cards

        var width: CGFloat? {
            switch self {
            case .small: return 60
            case .medium: return 80
            case .large: return nil
            }
        }

        var height: CGFloat {
            switch self {
            case .small: return 45
            case .medium: return 60
            case .large: return 150
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 20
            case .medium: return 24
            case .large: return 40
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 0
            }
        }
    }

    var body: some View {
        Group {
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholderView
                            .overlay { ProgressView().scaleEffect(size == .large ? 1.0 : 0.7) }
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                // No URL provided - show placeholder immediately without spinner
                placeholderView
            }
        }
        .frame(width: size.width, height: size.height)
        .cornerRadius(size.cornerRadius)
        .clipped()
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay {
                Image(systemName: iconForItemType)
                    .font(.system(size: size.iconSize))
                    .foregroundStyle(.secondary)
            }
    }

    /// Returns appropriate SF Symbol for the item type
    private var iconForItemType: String {
        switch itemType.lowercased() {
        case "sound":
            return "music.note"
        case "skin":
            return "paintbrush.fill"
        case "texture":
            return "square.grid.3x3.fill"
        case "model":
            return "cube.fill"
        case "map":
            return "map.fill"
        case "tool":
            return "wrench.and.screwdriver.fill"
        case "spray":
            return "paintbrush.pointed.fill"
        case "gui":
            return "rectangle.3.group.fill"
        case "wip":
            return "hammer.fill"
        case "mod":
            return "puzzlepiece.extension.fill"
        default:
            return "photo"
        }
    }
}

#Preview("ModThumbnailView Sizes") {
    VStack(spacing: 20) {
        Text("Small (Import Confirmation)")
        HStack(spacing: 10) {
            ModThumbnailView(imageURL: nil, itemType: "Mod", size: .small)
            ModThumbnailView(imageURL: nil, itemType: "Sound", size: .small)
            ModThumbnailView(imageURL: nil, itemType: "Texture", size: .small)
        }

        Text("Medium (List Row)")
        HStack(spacing: 10) {
            ModThumbnailView(imageURL: nil, itemType: "Mod", size: .medium)
            ModThumbnailView(imageURL: nil, itemType: "Sound", size: .medium)
            ModThumbnailView(imageURL: nil, itemType: "Skin", size: .medium)
        }

        Text("Large (Card)")
        HStack(spacing: 10) {
            ModThumbnailView(imageURL: nil, itemType: "Mod", size: .large)
                .frame(width: 150)
            ModThumbnailView(imageURL: nil, itemType: "Sound", size: .large)
                .frame(width: 150)
        }
    }
    .padding()
}
