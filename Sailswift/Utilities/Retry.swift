import Foundation

enum Retry {
    /// Run `operation`, retrying up to `maxAttempts` times. The delay grows
    /// linearly with each failed attempt (attempt * delayNanoseconds).
    /// Throws the last error once attempts are exhausted.
    static func withAttempts<T>(
        _ maxAttempts: Int,
        delayNanoseconds: UInt64 = 0,
        operation: () async throws -> T
    ) async throws -> T {
        precondition(maxAttempts > 0)
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxAttempts, delayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: delayNanoseconds * UInt64(attempt))
                }
            }
        }
        throw lastError!
    }
}
