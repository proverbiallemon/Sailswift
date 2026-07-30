import XCTest

final class LoadOrderDedupeTests: XCTestCase {
    func testRemovesDuplicatesKeepingFirstOccurrence() {
        XCTAssertEqual(["A", "A", "B"].removingDuplicatesKeepingFirst(), ["A", "B"])
    }

    func testPreservesOrderOfFirstOccurrences() {
        XCTAssertEqual(
            ["C", "A", "B", "A", "C", "D"].removingDuplicatesKeepingFirst(),
            ["C", "A", "B", "D"]
        )
    }

    func testEmptyArrayStaysEmpty() {
        XCTAssertEqual([String]().removingDuplicatesKeepingFirst(), [])
    }

    func testArrayWithoutDuplicatesIsUnchanged() {
        XCTAssertEqual(["A", "B", "C"].removingDuplicatesKeepingFirst(), ["A", "B", "C"])
    }
}
