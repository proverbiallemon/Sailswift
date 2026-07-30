import XCTest

final class ModDownloadRequestTests: XCTestCase {
    func testParsesStandardModURL() throws {
        let result = ModDownloadRequest.parse("shipofharkinian://https//gamebanana.com/mmdl/1513584,Mod,578470")
        let request = try result.get()
        XCTAssertEqual(request.fileId, "1513584")
        XCTAssertEqual(request.itemType, "Mod")
        XCTAssertEqual(request.modId, "578470")
    }

    func testParsesTextureItemType() throws {
        // Texture was silently rejected by the old URL-handler allowlist
        let result = ModDownloadRequest.parse("shipofharkinian://https//gamebanana.com/mmdl/111,Texture,222")
        XCTAssertEqual(try result.get().itemType, "Texture")
    }

    func testAcceptsEveryCanonicalItemType() {
        for itemType in ModDownloadRequest.validItemTypes {
            let result = ModDownloadRequest.parse("shipofharkinian://https//gamebanana.com/mmdl/1,\(itemType),2")
            XCTAssertNotNil(try? result.get(), "\(itemType) should parse")
        }
    }

    func testRejectsUnknownItemType() {
        let result = ModDownloadRequest.parse("shipofharkinian://https//gamebanana.com/mmdl/1,Sneaky,2")
        XCTAssertEqual(result, .failure(.unsupportedItemType("Sneaky")))
    }

    func testRejectsNonNumericFileId() {
        let result = ModDownloadRequest.parse("shipofharkinian://https//gamebanana.com/mmdl/abc,Mod,2")
        XCTAssertEqual(result, .failure(.invalidFileId))
    }

    func testRejectsNonNumericModId() {
        let result = ModDownloadRequest.parse("shipofharkinian://https//gamebanana.com/mmdl/1,Mod,../etc")
        XCTAssertEqual(result, .failure(.invalidModId))
    }

    func testRejectsNonModDownloadURL() {
        let result = ModDownloadRequest.parse("shipofharkinian://https//gamebanana.com/tools/21731")
        XCTAssertEqual(result, .failure(.notAModDownloadURL))
    }

    func testRejectsTooFewParameters() {
        let result = ModDownloadRequest.parse("shipofharkinian://https//gamebanana.com/mmdl/1513584,Mod")
        XCTAssertEqual(result, .failure(.notAModDownloadURL))
    }
}
