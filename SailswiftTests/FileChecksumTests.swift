import XCTest
import CryptoKit

final class FileChecksumTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ data: Data, name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testKnownHashOfSmallFile() throws {
        let url = try write(Data("hello world".utf8), name: "small.bin")
        XCTAssertEqual(try FileChecksum.md5(of: url), "5eb63bbbe01eeed093cb22bb8f5acdc3")
    }

    func testKnownHashOfEmptyFile() throws {
        let url = try write(Data(), name: "empty.bin")
        XCTAssertEqual(try FileChecksum.md5(of: url), "d41d8cd98f00b204e9800998ecf8427e")
    }

    func testFileLargerThanOneChunkMatchesWholeFileHash() throws {
        // 5 MB of pseudo-random-ish bytes spans multiple 1 MB chunks
        var data = Data(capacity: 5 * 1024 * 1024)
        var seed: UInt8 = 7
        for _ in 0..<(5 * 1024 * 1024) {
            data.append(seed)
            seed = seed &* 31 &+ 17
        }
        let url = try write(data, name: "large.bin")

        let expected = Insecure.MD5.hash(data: data)
            .map { String(format: "%02hhx", $0) }.joined()
        XCTAssertEqual(try FileChecksum.md5(of: url), expected)
    }

    func testMissingFileThrows() {
        let url = tempDir.appendingPathComponent("nope.bin")
        XCTAssertThrowsError(try FileChecksum.md5(of: url))
    }
}
