import Foundation
import CryptoKit

enum FileChecksum {
    /// MD5 of a file computed in 1 MB chunks, so multi-GB archives never
    /// have to fit in memory. Returns a lowercase hex string.
    static func md5(of url: URL, chunkSize: Int = 1024 * 1024) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = Insecure.MD5()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02hhx", $0) }.joined()
    }
}
