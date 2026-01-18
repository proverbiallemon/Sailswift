import Foundation

/// Represents a mod from the GameBanana API
struct GameBananaMod: Identifiable, Hashable {
    let modId: Int
    let name: String
    let author: String
    let imageURL: URL?
    let category: String
    let viewCount: Int
    let likeCount: Int
    let profileURL: URL
    let dateAdded: Date?
    let dateUpdated: Date?
    let hasFiles: Bool

    var id: Int { modId }

    var formattedViewCount: String { formatCount(viewCount) }
    var formattedLikeCount: String { formatCount(likeCount) }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

/// Represents a downloadable file from GameBanana
struct GameBananaFile: Identifiable, Hashable {
    let fileId: Int
    let filename: String
    let filesize: Int
    let downloadURL: URL
    let downloadCount: Int
    let md5: String
    let analysisResult: String

    var id: Int { fileId }

    var formattedFilesize: String {
        ByteCountFormatter.string(fromByteCount: Int64(filesize), countStyle: .file)
    }
}

/// Categories available for Ship of Harkinian mods
enum ModCategory: String, CaseIterable {
    case all = "All Categories"
    case models = "Models"
    case textures = "Textures"
    case otherMisc = "Other/Misc"
    case samples = "Samples"
    case music = "Music"
    case audio = "Audio"
    case skins = "Skins"
    case animations = "Animations"
    case voices = "Voices"

    var displayName: String { rawValue }
}

/// Sort options for mod browsing
enum ModSortOption: String, CaseIterable {
    case newest = "new"
    case updated = "updated"

    var displayName: String {
        switch self {
        case .newest: return "Newest"
        case .updated: return "Recently Updated"
        }
    }
}
