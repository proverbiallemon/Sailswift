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
    let itemType: String  // "Mod", "Sound", "Skin", etc.

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
    let dateAdded: Date?
    let isArchived: Bool

    var id: Int { fileId }

    var formattedFilesize: String {
        ByteCountFormatter.string(fromByteCount: Int64(filesize), countStyle: .file)
    }
}

/// Category filter for mod browsing
/// Uses "All" plus dynamically detected categories from cached mods
struct ModCategoryFilter: Hashable, Identifiable {
    let name: String
    let count: Int

    var id: String { name }

    var displayName: String {
        if name == "All" {
            return "All Categories"
        }
        return "\(name) (\(count))"
    }

    static let all = ModCategoryFilter(name: "All", count: 0)

    /// Build category filters from a list of mods
    static func fromMods(_ mods: [GameBananaMod]) -> [ModCategoryFilter] {
        // Count mods per category
        var categoryCounts: [String: Int] = [:]
        for mod in mods {
            let category = mod.category
            categoryCounts[category, default: 0] += 1
        }

        // Sort by count (descending), then alphabetically
        let sorted = categoryCounts.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            return lhs.key < rhs.key
        }

        // Build filter list with "All" first
        var filters = [ModCategoryFilter.all]
        filters.append(contentsOf: sorted.map { ModCategoryFilter(name: $0.key, count: $0.value) })

        return filters
    }
}

/// Sort options for mod browsing
enum ModSortOption: String, CaseIterable {
    case newest = "new"
    case updated = "updated"
    case popular = "popular"
    case mostLiked = "liked"

    var displayName: String {
        switch self {
        case .newest: return "Newest"
        case .updated: return "Updated"
        case .popular: return "Most Views"
        case .mostLiked: return "Most Liked"
        }
    }
}
