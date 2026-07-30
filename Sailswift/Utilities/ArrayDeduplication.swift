import Foundation

extension Array where Element: Hashable {
    /// Returns the array with duplicate elements removed, keeping the first
    /// occurrence of each and preserving relative order.
    func removingDuplicatesKeepingFirst() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
