import Foundation

/// Adds conservative paragraph structure to a complete grounded Email transcript.
/// It deliberately never rewrites tokens: optional model polishing happens later.
struct DeterministicEmailFormatter: Sendable {
    func format(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return source }

        let explicitParagraphs = trimmed.components(
            separatedBy: try! NSRegularExpression(pattern: #"\n\s*\n"#)
        )
        if explicitParagraphs.count > 1 {
            return explicitParagraphs
                .map(normalizeWhitespace)
                .filter { $0.isEmpty == false }
                .joined(separator: "\n\n")
        }

        let sentences = sentenceRanges(in: trimmed).map { normalizeWhitespace(String(trimmed[$0])) }
        guard sentences.count > 1 else { return normalizeWhitespace(trimmed) }

        var remaining = sentences
        var paragraphs: [String] = []
        if let first = remaining.first, isGreeting(first) {
            paragraphs.append(first)
            remaining.removeFirst()
        }
        let signoff: String?
        if let last = remaining.last, isSignoff(last) {
            signoff = last
            remaining.removeLast()
        } else {
            signoff = nil
        }
        while remaining.isEmpty == false {
            paragraphs.append(remaining.prefix(2).joined(separator: " "))
            remaining.removeFirst(min(2, remaining.count))
        }
        if let signoff { paragraphs.append(signoff) }
        return paragraphs.joined(separator: "\n\n")
    }

    private func sentenceRanges(in text: String) -> [Range<String.Index>] {
        let pattern = #".*?[.!?](?=\s+|$)|.+$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        else { return [text.startIndex..<text.endIndex] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text)
        }
    }

    private func normalizeWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isGreeting(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return ["hi ", "hello ", "dear ", "respected ", "good morning ", "good afternoon ", "good evening "]
            .contains { lower.hasPrefix($0) }
    }

    private func isSignoff(_ sentence: String) -> Bool {
        let lower = sentence.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return ["thanks", "thank you", "regards", "best", "best regards", "sincerely"]
            .contains { lower == $0 || lower.hasPrefix("\($0) ") || lower.hasPrefix("\($0),") }
    }
}

private extension String {
    func components(separatedBy expression: NSRegularExpression) -> [String] {
        let fullRange = NSRange(startIndex..<endIndex, in: self)
        var result: [String] = []
        var cursor = startIndex
        for match in expression.matches(in: self, range: fullRange) {
            guard let range = Range(match.range, in: self) else { continue }
            result.append(String(self[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }
        result.append(String(self[cursor..<endIndex]))
        return result
    }
}
