import Foundation

/// Shared cache for GameBanana mods - loads once and is available everywhere
@MainActor
class GameBananaModCache: ObservableObject {
    static let shared = GameBananaModCache()

    @Published var mods: [GameBananaMod] = []
    @Published var isLoading = false
    @Published var loadProgress: String = ""
    @Published var hasLoaded = false

    private var currentPage = 1
    private var hasMore = true

    private init() {}

    func loadAllIfNeeded() async {
        guard !hasLoaded && !isLoading else { return }
        await loadAll()
    }

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        loadProgress = "Loading mods..."
        currentPage = 1
        mods = []
        hasMore = true

        let api = GameBananaAPI.shared

        while hasMore {
            do {
                let result = try await api.fetchMods(page: currentPage, perPage: 50, sort: .newest, search: nil)
                mods.append(contentsOf: result.mods)
                hasMore = result.hasMore
                loadProgress = "\(mods.count) mods loaded..."
                currentPage += 1

                // Small delay to avoid hammering the API
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                print("Error loading mods: \(error)")
                break
            }
        }

        hasLoaded = true
        isLoading = false
        loadProgress = ""
    }

    func reload() async {
        hasLoaded = false
        await loadAll()
    }
}

/// API client for GameBanana
class GameBananaAPI {
    static let shared = GameBananaAPI()

    private let baseURL = "https://gamebanana.com/apiv11"
    private let sohGameId = "16121"
    private let userAgent = "Sailswift/1.0 (Ship of Harkinian Mod Manager)"
    private let session: URLSession

    /// Valid GameBanana item types for URL path sanitization
    private let validItemTypes: Set<String> = ["Mod", "Sound", "Skin", "Texture", "Model", "Map", "Tool", "Spray", "Gui", "Wip"]

    /// Sanitize item type to prevent URL injection
    private func sanitizeItemType(_ itemType: String) -> String {
        return validItemTypes.contains(itemType) ? itemType : "Mod"
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    /// Fetch mods for Ship of Harkinian
    func fetchMods(
        page: Int = 1,
        perPage: Int = 15,
        sort: ModSortOption = .newest,
        search: String? = nil
    ) async throws -> (mods: [GameBananaMod], total: Int, hasMore: Bool) {
        if let search = search, !search.isEmpty {
            return try await searchMods(term: search, page: page, perPage: perPage)
        } else {
            return try await browseMods(page: page, perPage: perPage, sort: sort)
        }
    }

    private func browseMods(page: Int, perPage: Int, sort: ModSortOption) async throws -> (mods: [GameBananaMod], total: Int, hasMore: Bool) {
        var components = URLComponents(string: "\(baseURL)/Game/\(sohGameId)/Subfeed")!
        components.queryItems = [
            URLQueryItem(name: "_nPage", value: String(page)),
            URLQueryItem(name: "_nPerpage", value: String(perPage)),
            URLQueryItem(name: "_sSort", value: sort.rawValue),
            URLQueryItem(name: "_aFilters[Generic_Category]", value: "Mod")
        ]

        let (data, _) = try await session.data(from: components.url!)
        return try parseModResponse(data)
    }

    private func searchMods(term: String, page: Int, perPage: Int) async throws -> (mods: [GameBananaMod], total: Int, hasMore: Bool) {
        var components = URLComponents(string: "\(baseURL)/Util/Search/Results")!
        components.queryItems = [
            URLQueryItem(name: "_sSearchString", value: term),
            URLQueryItem(name: "_nPage", value: String(page)),
            URLQueryItem(name: "_nPerpage", value: String(perPage)),
            URLQueryItem(name: "_idGameRow", value: sohGameId)
        ]

        let (data, _) = try await session.data(from: components.url!)
        return try parseModResponse(data)
    }

    private func parseModResponse(_ data: Data) throws -> (mods: [GameBananaMod], total: Int, hasMore: Bool) {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let metadata = json["_aMetadata"] as? [String: Any] ?? [:]
        let totalCount = metadata["_nRecordCount"] as? Int ?? 0
        let isComplete = metadata["_bIsComplete"] as? Bool ?? true
        let records = json["_aRecords"] as? [[String: Any]] ?? []
        let mods = records.compactMap { parseModRecord($0) }
        return (mods, totalCount, !isComplete)
    }

    private func parseModRecord(_ record: [String: Any]) -> GameBananaMod? {
        guard let modId = record["_idRow"] as? Int else { return nil }

        // Filter out non-downloadable content types
        let modelName = record["_sModelName"] as? String ?? "Mod"
        if modelName == "Question" { return nil }

        var imageURL: URL? = nil
        if let previewMedia = record["_aPreviewMedia"] as? [String: Any],
           let images = previewMedia["_aImages"] as? [[String: Any]],
           let firstImage = images.first,
           let baseURL = firstImage["_sBaseUrl"] as? String,
           let file220 = firstImage["_sFile220"] as? String {
            imageURL = URL(string: "\(baseURL)/\(file220)")
        }

        let submitter = record["_aSubmitter"] as? [String: Any]
        let author = submitter?["_sName"] as? String ?? "Unknown"
        let rootCategory = record["_aRootCategory"] as? [String: Any]
        let category = rootCategory?["_sName"] as? String ?? "Unknown"
        let profileURLString = record["_sProfileUrl"] as? String ?? "https://gamebanana.com/mods/\(modId)"

        var dateAdded: Date? = nil
        var dateUpdated: Date? = nil
        if let timestamp = record["_tsDateAdded"] as? Int {
            dateAdded = Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
        if let timestamp = record["_tsDateUpdated"] as? Int {
            dateUpdated = Date(timeIntervalSince1970: TimeInterval(timestamp))
        }

        // Get item type from _sModelName (e.g., "Mod", "Sound", "Skin")
        let itemType = record["_sModelName"] as? String ?? "Mod"

        return GameBananaMod(
            modId: modId,
            name: record["_sName"] as? String ?? "Mod #\(modId)",
            author: author,
            imageURL: imageURL,
            category: category,
            viewCount: record["_nViewCount"] as? Int ?? 0,
            likeCount: record["_nLikeCount"] as? Int ?? 0,
            profileURL: URL(string: profileURLString)!,
            dateAdded: dateAdded,
            dateUpdated: dateUpdated,
            hasFiles: record["_bHasFiles"] as? Bool ?? false,
            itemType: itemType
        )
    }

    /// Fetch downloadable files for a mod/sound/skin/etc.
    func fetchModFiles(modId: Int, itemType: String = "Mod") async throws -> [GameBananaFile] {
        let safeItemType = sanitizeItemType(itemType)

        // For Mod type, use the /Files endpoint
        // For other types (Sound, Skin, etc.), fetch item with _aFiles property
        if safeItemType == "Mod" {
            let url = URL(string: "\(baseURL)/Mod/\(modId)/Files")!
            let (data, _) = try await session.data(from: url)

            guard let files = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }

            return parseFileArray(files)
        } else {
            // For non-Mod types, fetch the item with _aFiles included
            var components = URLComponents(string: "\(baseURL)/\(safeItemType)/\(modId)")!
            components.queryItems = [
                URLQueryItem(name: "_csvProperties", value: "_aFiles")
            ]

            let (data, _) = try await session.data(from: components.url!)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let files = json["_aFiles"] as? [[String: Any]] else {
                return []
            }

            return parseFileArray(files)
        }
    }

    /// Parse an array of file info dictionaries into GameBananaFile objects
    /// Returns files sorted: non-archived first (by date), then archived (by date)
    private func parseFileArray(_ files: [[String: Any]]) -> [GameBananaFile] {
        let parsed = files.compactMap { fileInfo -> GameBananaFile? in
            guard let fileId = fileInfo["_idRow"] as? Int,
                  let downloadURLString = fileInfo["_sDownloadUrl"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                return nil
            }

            // Parse date added timestamp
            var dateAdded: Date? = nil
            if let timestamp = fileInfo["_tsDateAdded"] as? Int {
                dateAdded = Date(timeIntervalSince1970: TimeInterval(timestamp))
            }

            // Parse archived status
            let isArchived = fileInfo["_bIsArchived"] as? Bool ?? false

            return GameBananaFile(
                fileId: fileId,
                filename: fileInfo["_sFile"] as? String ?? "",
                filesize: fileInfo["_nFilesize"] as? Int ?? 0,
                downloadURL: downloadURL,
                downloadCount: fileInfo["_nDownloadCount"] as? Int ?? 0,
                md5: fileInfo["_sMd5Checksum"] as? String ?? "",
                analysisResult: fileInfo["_sAnalysisResult"] as? String ?? "",
                dateAdded: dateAdded,
                isArchived: isArchived
            )
        }

        // Sort: non-archived first (by date desc), then archived (by date desc)
        return parsed.sorted { file1, file2 in
            // Non-archived files come before archived
            if file1.isArchived != file2.isArchived {
                return !file1.isArchived
            }
            // Within same archive status, sort by date (newest first)
            guard let date1 = file1.dateAdded else { return false }
            guard let date2 = file2.dateAdded else { return true }
            return date1 > date2
        }
    }

    /// Fetch mod details by ID
    func fetchModDetails(modId: Int, itemType: String = "Mod") async throws -> GameBananaMod? {
        let safeItemType = sanitizeItemType(itemType)
        var components = URLComponents(string: "\(baseURL)/\(safeItemType)/\(modId)")!
        components.queryItems = [
            URLQueryItem(name: "_csvProperties", value: "_idRow,_sName,_aSubmitter,_aPreviewMedia,_aRootCategory,_nViewCount,_nLikeCount,_sProfileUrl,_tsDateAdded,_tsDateUpdated")
        ]

        let (data, _) = try await session.data(from: components.url!)

        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Check for API error
        if record["_sErrorCode"] != nil {
            return nil
        }

        return parseModRecord(record)
    }

    /// Fetch a specific file by ID (used for URL scheme handling)
    func fetchFileInfo(fileId: Int) async throws -> GameBananaFile? {
        let url = URL(string: "\(baseURL)/File/\(fileId)")!
        let (data, _) = try await session.data(from: url)

        guard let fileInfo = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let downloadURLString = fileInfo["_sDownloadUrl"] as? String,
              let downloadURL = URL(string: downloadURLString) else {
            return nil
        }

        // Parse date added timestamp
        var dateAdded: Date? = nil
        if let timestamp = fileInfo["_tsDateAdded"] as? Int {
            dateAdded = Date(timeIntervalSince1970: TimeInterval(timestamp))
        }

        // Parse archived status
        let isArchived = fileInfo["_bIsArchived"] as? Bool ?? false

        return GameBananaFile(
            fileId: fileId,
            filename: fileInfo["_sFile"] as? String ?? "",
            filesize: fileInfo["_nFilesize"] as? Int ?? 0,
            downloadURL: downloadURL,
            downloadCount: fileInfo["_nDownloadCount"] as? Int ?? 0,
            md5: fileInfo["_sMd5Checksum"] as? String ?? "",
            analysisResult: fileInfo["_sAnalysisResult"] as? String ?? "",
            dateAdded: dateAdded,
            isArchived: isArchived
        )
    }
}
