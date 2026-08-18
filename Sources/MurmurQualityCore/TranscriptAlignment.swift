import Foundation

public struct TranscriptToken: Codable, Equatable, Sendable {
    public let original: String
    public let normalized: String
    public let startOffset: Int
    public let endOffset: Int
}

public enum TranscriptEditKind: String, Codable, Equatable, Sendable {
    case match
    case substitution
    case insertion
    case deletion
}

public struct TranscriptEdit: Codable, Equatable, Sendable {
    public let kind: TranscriptEditKind
    public let expected: TranscriptToken?
    public let actual: TranscriptToken?
}

public struct TranscriptSourceSpan: Codable, Equatable, Sendable {
    public let startOffset: Int
    public let endOffset: Int
    public let text: String
    public let tokenCount: Int
}

public struct TranscriptAlignmentResult: Codable, Equatable, Sendable {
    public let operations: [TranscriptEdit]
    public let wordErrorRate: Double
    public let characterErrorRate: Double
    public let longestMissingSourceSpan: TranscriptSourceSpan?
}

public enum TranscriptNormalizer {
    private static let tokenExpression = try! NSRegularExpression(
        pattern: #"[\p{L}\p{N}_]+(?:['’\-][\p{L}\p{N}_]+)*"#
    )

    public static func tokens(in text: String) -> [TranscriptToken] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return tokenExpression.matches(in: text, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let original = String(text[range])
            return TranscriptToken(
                original: original,
                normalized: normalizeToken(original),
                startOffset: text.distance(from: text.startIndex, to: range.lowerBound),
                endOffset: text.distance(from: text.startIndex, to: range.upperBound)
            )
        }
    }

    public static func normalizedText(_ text: String) -> String {
        tokens(in: text).map(\.normalized).joined(separator: " ")
    }

    public static func normalizeToken(_ token: String) -> String {
        token
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

public enum TranscriptAligner {
    public static func align(expected: String, actual: String) -> TranscriptAlignmentResult {
        let expectedTokens = TranscriptNormalizer.tokens(in: expected)
        let actualTokens = TranscriptNormalizer.tokens(in: actual)
        let operations = align(expected: expectedTokens, actual: actualTokens)
        let substitutions = operations.filter { $0.kind == .substitution }.count
        let insertions = operations.filter { $0.kind == .insertion }.count
        let deletions = operations.filter { $0.kind == .deletion }.count
        let wordErrorRate = Self.errorRate(
            errors: substitutions + insertions + deletions,
            expectedCount: expectedTokens.count
        )
        let expectedCharacters = Array(TranscriptNormalizer.normalizedText(expected))
        let actualCharacters = Array(TranscriptNormalizer.normalizedText(actual))
        let characterErrors = levenshteinDistance(expectedCharacters, actualCharacters)
        let characterErrorRate = errorRate(errors: characterErrors, expectedCount: expectedCharacters.count)

        return TranscriptAlignmentResult(
            operations: operations,
            wordErrorRate: wordErrorRate,
            characterErrorRate: characterErrorRate,
            longestMissingSourceSpan: longestDeletionSpan(operations: operations, expectedText: expected)
        )
    }

    private static func align(expected: [TranscriptToken], actual: [TranscriptToken]) -> [TranscriptEdit] {
        let rows = expected.count + 1
        let columns = actual.count + 1
        var costs = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        for row in 0..<rows { costs[row][0] = row }
        for column in 0..<columns { costs[0][column] = column }

        if expected.isEmpty {
            return actual.map { TranscriptEdit(kind: .insertion, expected: nil, actual: $0) }
        }
        if actual.isEmpty {
            return expected.map { TranscriptEdit(kind: .deletion, expected: $0, actual: nil) }
        }

        for row in 1..<rows {
            for column in 1..<columns {
                let substitutionCost = expected[row - 1].normalized == actual[column - 1].normalized ? 0 : 1
                costs[row][column] = min(
                    costs[row - 1][column - 1] + substitutionCost,
                    costs[row - 1][column] + 1,
                    costs[row][column - 1] + 1
                )
            }
        }

        var operations: [TranscriptEdit] = []
        var row = expected.count
        var column = actual.count
        while row > 0 || column > 0 {
            if row > 0, column > 0 {
                let matches = expected[row - 1].normalized == actual[column - 1].normalized
                let diagonalCost = costs[row - 1][column - 1] + (matches ? 0 : 1)
                if costs[row][column] == diagonalCost {
                    operations.append(TranscriptEdit(
                        kind: matches ? .match : .substitution,
                        expected: expected[row - 1],
                        actual: actual[column - 1]
                    ))
                    row -= 1
                    column -= 1
                    continue
                }
            }
            if row > 0, costs[row][column] == costs[row - 1][column] + 1 {
                operations.append(TranscriptEdit(kind: .deletion, expected: expected[row - 1], actual: nil))
                row -= 1
                continue
            }
            operations.append(TranscriptEdit(kind: .insertion, expected: nil, actual: actual[column - 1]))
            column -= 1
        }
        return operations.reversed()
    }

    private static func longestDeletionSpan(
        operations: [TranscriptEdit],
        expectedText: String
    ) -> TranscriptSourceSpan? {
        var best: [TranscriptToken] = []
        var current: [TranscriptToken] = []
        for operation in operations {
            if operation.kind == .deletion, let token = operation.expected {
                current.append(token)
            } else {
                if current.count > best.count { best = current }
                current = []
            }
        }
        if current.count > best.count { best = current }
        guard let first = best.first, let last = best.last else { return nil }
        let lower = expectedText.index(expectedText.startIndex, offsetBy: first.startOffset)
        let upper = expectedText.index(expectedText.startIndex, offsetBy: last.endOffset)
        return TranscriptSourceSpan(
            startOffset: first.startOffset,
            endOffset: last.endOffset,
            text: String(expectedText[lower..<upper]),
            tokenCount: best.count
        )
    }

    static func errorRate(errors: Int, expectedCount: Int) -> Double {
        if expectedCount == 0 { return errors == 0 ? 0 : 1 }
        return Double(errors) / Double(expectedCount)
    }

    static func levenshteinDistance<Element: Equatable>(_ source: [Element], _ target: [Element]) -> Int {
        if source.isEmpty { return target.count }
        if target.isEmpty { return source.count }
        var previous = Array(0...target.count)
        for (sourceIndex, sourceValue) in source.enumerated() {
            var current = Array(repeating: 0, count: target.count + 1)
            current[0] = sourceIndex + 1
            for (targetIndex, targetValue) in target.enumerated() {
                current[targetIndex + 1] = min(
                    previous[targetIndex + 1] + 1,
                    current[targetIndex] + 1,
                    previous[targetIndex] + (sourceValue == targetValue ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[target.count]
    }
}

public enum TranscriptCompletenessReason: Codable, Equatable, Sendable {
    case missingRequiredPhrase(RequiredPhrase)
    case missingProtectedToken(String)
}

public struct TranscriptCompletenessResult: Codable, Equatable, Sendable {
    public let isComplete: Bool
    public let reasons: [TranscriptCompletenessReason]
    public let alignment: TranscriptAlignmentResult
    public let longestMissingSourceSpan: TranscriptSourceSpan?
}

public enum TranscriptCompletenessAnalyzer {
    public static func analyze(
        expected: String,
        actual: String,
        requiredPhrases: [RequiredPhrase],
        protectedTokens: [String]
    ) -> TranscriptCompletenessResult {
        let alignment = TranscriptAligner.align(expected: expected, actual: actual)
        let actualTokens = TranscriptNormalizer.tokens(in: actual).map(\.normalized)
        var reasons: [TranscriptCompletenessReason] = []

        for phrase in requiredPhrases {
            let phraseTokens = TranscriptNormalizer.tokens(in: phrase.text).map(\.normalized)
            if phraseTokens.isEmpty || !containsContiguous(actualTokens, phraseTokens) {
                reasons.append(.missingRequiredPhrase(phrase))
            }
        }
        for protectedToken in protectedTokens {
            let tokenParts = TranscriptNormalizer.tokens(in: protectedToken).map(\.normalized)
            if tokenParts.isEmpty || !containsContiguous(actualTokens, tokenParts) {
                reasons.append(.missingProtectedToken(protectedToken))
            }
        }

        return TranscriptCompletenessResult(
            isComplete: reasons.isEmpty,
            reasons: reasons,
            alignment: alignment,
            longestMissingSourceSpan: alignment.longestMissingSourceSpan
        )
    }

    private static func containsContiguous(_ source: [String], _ target: [String]) -> Bool {
        guard !target.isEmpty, target.count <= source.count else { return false }
        if target.count == source.count { return source == target }
        for start in 0...(source.count - target.count) {
            if Array(source[start..<(start + target.count)]) == target { return true }
        }
        return false
    }
}
