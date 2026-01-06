import Foundation

extension String {

    /// Sanitize folder name to extract clean label
    /// Examples:
    ///   "12. Dog" → "Dog"
    ///   "1. Cat" → "Cat"
    ///   "  5.  Bird  " → "Bird"
    ///   "Hello World" → "Hello World"
    ///   "123" → "123" (numbers only, keep as-is)
    ///   "" → ""
    func sanitizedLabel() -> String {
        // Pattern: optional whitespace, one or more digits, optional dot, optional whitespace
        // This matches things like "  12. " or "5." or "  123  "
        let pattern = "^\\s*\\d+\\.?\\s*"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return self.trimmingCharacters(in: .whitespaces)
        }

        let range = NSRange(self.startIndex..., in: self)
        let result = regex.stringByReplacingMatches(
            in: self,
            options: [],
            range: range,
            withTemplate: ""
        )

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Check if string is valid filename (no illegal characters)
    var isValidFilename: Bool {
        // Check not empty or just whitespace
        let trimmed = self.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return false
        }

        // Check for illegal filename characters: / \ : * ? " < > |
        let illegalCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return self.rangeOfCharacter(from: illegalCharacters) == nil
    }

    /// Convert to safe filename by replacing illegal characters
    func toSafeFilename() -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let components = self.components(separatedBy: illegalCharacters)
        return components.joined(separator: "_").trimmingCharacters(in: .whitespaces)
    }
}
