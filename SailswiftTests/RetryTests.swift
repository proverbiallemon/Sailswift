import XCTest

final class RetryTests: XCTestCase {
    struct TestError: Error, Equatable {
        let id: Int
    }

    func testReturnsImmediatelyOnFirstSuccess() async throws {
        var attempts = 0
        let value = try await Retry.withAttempts(3) {
            attempts += 1
            return "ok"
        }
        XCTAssertEqual(value, "ok")
        XCTAssertEqual(attempts, 1)
    }

    func testRetriesUntilSuccess() async throws {
        var attempts = 0
        let value = try await Retry.withAttempts(3) {
            attempts += 1
            if attempts < 3 { throw TestError(id: attempts) }
            return "recovered"
        }
        XCTAssertEqual(value, "recovered")
        XCTAssertEqual(attempts, 3)
    }

    func testThrowsLastErrorAfterExhaustingAttempts() async {
        var attempts = 0
        do {
            _ = try await Retry.withAttempts(3) { () -> String in
                attempts += 1
                throw TestError(id: attempts)
            }
            XCTFail("should have thrown")
        } catch {
            XCTAssertEqual(error as? TestError, TestError(id: 3), "last error should propagate")
        }
        XCTAssertEqual(attempts, 3)
    }
}
