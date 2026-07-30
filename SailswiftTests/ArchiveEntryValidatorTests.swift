import XCTest

final class ArchiveEntryValidatorTests: XCTestCase {
    func testAcceptsNormalEntries() {
        XCTAssertNoThrow(try ArchiveEntryValidator.validate(entries: [
            "mod.otr",
            "textures/pack.o2r",
            "deep/nested/dir/file.otr",
            "readme.txt"
        ]))
    }

    func testRejectsParentDirectoryTraversal() {
        XCTAssertThrowsError(try ArchiveEntryValidator.validate(entries: ["../evil.otr"])) { error in
            XCTAssertEqual(error as? ArchiveEntryValidator.ValidationError, .pathTraversal("../evil.otr"))
        }
    }

    func testRejectsNestedTraversal() {
        XCTAssertThrowsError(try ArchiveEntryValidator.validate(entries: ["mods/../../../etc/evil"]))
    }

    func testRejectsWindowsStyleTraversal() {
        XCTAssertThrowsError(try ArchiveEntryValidator.validate(entries: ["..\\evil.otr"]))
    }

    func testRejectsAbsolutePaths() {
        XCTAssertThrowsError(try ArchiveEntryValidator.validate(entries: ["/tmp/evil.otr"])) { error in
            XCTAssertEqual(error as? ArchiveEntryValidator.ValidationError, .absolutePath("/tmp/evil.otr"))
        }
    }

    func testAcceptsDotDotAsPartOfFilename() {
        // "..name" is a legal filename, not a traversal
        XCTAssertNoThrow(try ArchiveEntryValidator.validate(entries: ["mods/..hidden.otr", "a..b/file.otr"]))
    }

    func testAcceptsEmptyListing() {
        XCTAssertNoThrow(try ArchiveEntryValidator.validate(entries: []))
    }
}
