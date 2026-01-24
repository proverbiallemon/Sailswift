import Foundation
import SwiftUI

// MARK: - String Fuzzy Matching

extension String {
    /// Performs fuzzy matching - checks if all characters in the pattern appear in order
    /// Returns a score (higher is better match), or nil if no match
    func fuzzyMatch(_ pattern: String) -> Int? {
        let text = self.lowercased()
        let pattern = pattern.lowercased()

        guard !pattern.isEmpty else { return 0 }

        var score = 0
        var textIndex = text.startIndex
        var patternIndex = pattern.startIndex
        var consecutiveBonus = 0
        var lastMatchIndex: String.Index?

        while textIndex < text.endIndex && patternIndex < pattern.endIndex {
            let textChar = text[textIndex]
            let patternChar = pattern[patternIndex]

            if textChar == patternChar {
                // Base score for match
                score += 1

                // Bonus for consecutive matches
                if let last = lastMatchIndex, text.index(after: last) == textIndex {
                    consecutiveBonus += 2
                    score += consecutiveBonus
                } else {
                    consecutiveBonus = 0
                }

                // Bonus for matching at start
                if textIndex == text.startIndex {
                    score += 5
                }

                // Bonus for matching after separator (space, dash, underscore)
                if textIndex > text.startIndex {
                    let prevIndex = text.index(before: textIndex)
                    let prevChar = text[prevIndex]
                    if prevChar == " " || prevChar == "-" || prevChar == "_" {
                        score += 3
                    }
                }

                lastMatchIndex = textIndex
                patternIndex = pattern.index(after: patternIndex)
            }

            textIndex = text.index(after: textIndex)
        }

        // All pattern characters must be found
        if patternIndex == pattern.endIndex {
            // Bonus for shorter strings (more relevant match)
            let lengthBonus = max(0, 20 - (text.count - pattern.count))
            return score + lengthBonus
        }

        return nil
    }

    /// Simple check if string fuzzy matches pattern
    func fuzzyContains(_ pattern: String) -> Bool {
        return fuzzyMatch(pattern) != nil
    }
}

// MARK: - URL Extensions

extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    var fileSize: Int? {
        (try? resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
}

// MARK: - Date Extensions

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Color Extensions

extension Color {
    static let modEnabled = Color.green
    static let modDisabled = Color.red
    static let modMixed = Color.orange

    // Retro branding palette (matches website)
    static let retroRed = Color(red: 224/255, green: 64/255, blue: 64/255)
    static let retroOrange = Color(red: 255/255, green: 140/255, blue: 0/255)
    static let retroBlue = Color(red: 0/255, green: 102/255, blue: 204/255)
    static let retroBlueDark = Color(red: 0/255, green: 51/255, blue: 102/255)
}

// MARK: - Pixel Font

extension Font {
    /// Press Start 2P pixel font for retro branding accents
    static func pixel(size: CGFloat) -> Font {
        .custom("PressStart2P-Regular", size: size)
    }
}

// MARK: - View Extensions

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
