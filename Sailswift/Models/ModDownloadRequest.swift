import Foundation

/// A parsed one-click install request from the shipofharkinian:// URL scheme.
/// Format: shipofharkinian://https//gamebanana.com/mmdl/{fileId},{itemType},{modId}
struct ModDownloadRequest: Equatable {
    /// Canonical GameBanana item types Sailswift can handle.
    /// Single source of truth for the URL handler and GameBananaAPI.
    static let validItemTypes: Set<String> = [
        "Mod", "Sound", "Skin", "Texture", "Model", "Map", "Tool", "Spray", "Gui", "Wip"
    ]

    let fileId: String
    let itemType: String
    let modId: String

    enum ParseError: Error, Equatable {
        case notAModDownloadURL
        case invalidFileId
        case invalidModId
        case unsupportedItemType(String)
    }

    static func parse(_ urlString: String) -> Result<ModDownloadRequest, ParseError> {
        let withoutScheme = urlString.replacingOccurrences(of: "shipofharkinian://", with: "")
        let fixedURL = withoutScheme.replacingOccurrences(of: "https//", with: "https://")

        guard fixedURL.contains("gamebanana.com/mmdl/") else {
            return .failure(.notAModDownloadURL)
        }
        let components = fixedURL.components(separatedBy: "/mmdl/")
        guard components.count == 2 else {
            return .failure(.notAModDownloadURL)
        }
        let params = components[1].components(separatedBy: ",")
        guard params.count >= 3 else {
            return .failure(.notAModDownloadURL)
        }

        let fileId = params[0]
        let itemType = params[1]
        let modId = params[2]

        guard !fileId.isEmpty, fileId.allSatisfy({ $0.isNumber }) else {
            return .failure(.invalidFileId)
        }
        guard !modId.isEmpty, modId.allSatisfy({ $0.isNumber }) else {
            return .failure(.invalidModId)
        }
        guard validItemTypes.contains(itemType) else {
            return .failure(.unsupportedItemType(itemType))
        }

        return .success(ModDownloadRequest(fileId: fileId, itemType: itemType, modId: modId))
    }
}
