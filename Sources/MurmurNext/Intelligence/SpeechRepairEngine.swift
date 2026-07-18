import Foundation

enum SpeechRepairEditKind: String, Equatable, Sendable {
    case fillerRemoval
    case repetitionRemoval
    case explicitCorrection
    case abandonedClause
    case punctuationCleanup
}

struct SpeechRepairEdit: Equatable, Sendable {
    let kind: SpeechRepairEditKind
    let original: String
    let replacement: String
}

struct SpeechRepairResult: Equatable, Sendable {
    let text: String
    let edits: [SpeechRepairEdit]
}

struct SpeechRepairEngine: Sendable {
    func repair(_ transcript: String) -> SpeechRepairResult {
        var working = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard working.isEmpty == false else { return SpeechRepairResult(text: "", edits: []) }

        var edits: [SpeechRepairEdit] = []
        working = normalizeRepairPunctuation(in: working)
        working = removeFillers(from: working, edits: &edits)
        working = resolveRestartMarkers(in: working, edits: &edits)
        working = resolveAbandonedClauses(in: working, edits: &edits)
        working = resolveReplacementCorrections(in: working, edits: &edits)
        working = removeImmediateRepetitions(from: working, edits: &edits)
        working = removeRepeatedPhrases(from: working, edits: &edits)
        working = cleanPunctuation(in: working, edits: &edits)
        return SpeechRepairResult(text: working, edits: edits)
    }

    private func normalizeRepairPunctuation(in text: String) -> String {
        text
            .replacingOccurrences(
                of: #"—\s*(?=(?:sorry|i mean|actually|no\b|or rather|rather)\b)"#,
                with: ", ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"\b(sorry|i mean|actually|no|or rather|rather)\s*—\s*"#,
                with: "$1, ",
                options: [.regularExpression, .caseInsensitive]
            )
    }

    private func resolveRestartMarkers(in text: String, edits: inout [SpeechRepairEdit]) -> String {
        let pattern = #"(?i)(?:^|.*?[.!?])?\s*(?:scratch that|start over|start again|let me rephrase)[.!?,—-]*\s*"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range, in: text)
        else { return text }

        let replacement = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard replacement.isEmpty == false else { return text }
        edits.append(
            SpeechRepairEdit(
                kind: .abandonedClause,
                original: String(text[..<range.upperBound]),
                replacement: ""
            )
        )
        return replacement
    }

    private func removeFillers(from text: String, edits: inout [SpeechRepairEdit]) -> String {
        let pattern = #"(?i)(?:,\s*)?\b(?:um+|uh+|er+|erm+|hmm+)\b(?:,\s*)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let matches = expression.matches(in: text, range: range)
        guard matches.isEmpty == false else { return text }

        for match in matches {
            if let matchRange = Range(match.range, in: text) {
                edits.append(
                    SpeechRepairEdit(
                        kind: .fillerRemoval,
                        original: String(text[matchRange]),
                        replacement: ""
                    )
                )
            }
        }
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    private func resolveAbandonedClauses(in text: String, edits: inout [SpeechRepairEdit]) -> String {
        let markerPattern = #"(?i)\s*[,—-]?\s*no\s*,?\s*wait\s*[,—-]?\s*"#
        guard let marker = text.range(of: markerPattern, options: .regularExpression) else { return text }

        let before = String(text[..<marker.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let after = String(text[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let auxiliaries = ["should", "could", "would", "will", "can", "must", "might", "may"]
        let beforeWords = before.split(separator: " ").map(String.init)
        guard let auxiliaryIndex = beforeWords.lastIndex(where: { auxiliaries.contains(Self.bareWord($0).lowercased()) }) else {
            return text
        }

        let retained = beforeWords[...auxiliaryIndex].joined(separator: " ")
        let abandoned = beforeWords.dropFirst(auxiliaryIndex + 1).joined(separator: " ")
        edits.append(SpeechRepairEdit(kind: .abandonedClause, original: abandoned, replacement: ""))
        return "\(retained) \(after)"
    }

    private func resolveReplacementCorrections(in text: String, edits: inout [SpeechRepairEdit]) -> String {
        var tokens = Self.tokenize(text)
        let markerSequences = [
            ["i", "mean"],
            ["sorry"],
            ["or", "rather"],
            ["rather"],
            ["actually"],
            ["no"],
        ]
        var index = 0

        while index < tokens.count {
            guard let markerLength = markerSequences.first(where: { sequence in
                guard index + sequence.count <= tokens.count else { return false }
                return zip(tokens[index..<(index + sequence.count)], sequence).allSatisfy {
                    Self.bareWord($0.0).lowercased() == $0.1
                }
            })?.count else {
                index += 1
                continue
            }

            guard index > 0, index + markerLength < tokens.count else {
                index += markerLength
                continue
            }

            let nextTokenIndex = index + markerLength
            let nextToken = tokens[nextTokenIndex]
            let normalizedMarker = Self.bareWord(tokens[index]).lowercased()
            let previousContainsPause = tokens[index - 1].contains(",") || tokens[index - 1].contains("—")
            let replacementKind = Self.semanticKind(of: nextToken)
            let actuallyHasStrongReplacement = replacementKind == .number || replacementKind == .weekday || replacementKind == .capitalized
            if normalizedMarker == "actually", previousContainsPause == false, actuallyHasStrongReplacement == false {
                index += markerLength
                continue
            }
            if normalizedMarker == "no", previousContainsPause == false {
                index += markerLength
                continue
            }
            let previousIndex = replacementTargetIndex(before: index, replacementToken: nextToken, tokens: tokens)
            guard let previousIndex else {
                index += markerLength
                continue
            }

            let markerText = tokens[index..<(index + markerLength)].joined(separator: " ")
            let previous = tokens[previousIndex]
            edits.append(
                SpeechRepairEdit(
                    kind: .explicitCorrection,
                    original: "\(previous) \(markerText)",
                    replacement: nextToken
                )
            )

            tokens.removeSubrange(previousIndex..<(index + markerLength))
            index = previousIndex + 1
        }

        return tokens.joined(separator: " ")
    }

    private func removeRepeatedPhrases(from text: String, edits: inout [SpeechRepairEdit]) -> String {
        var tokens = Self.tokenize(text)
        guard tokens.count >= 4 else { return text }
        var phraseLength = min(6, tokens.count / 2)

        while phraseLength >= 2 {
            var index = 0
            while index + (phraseLength * 2) <= tokens.count {
                let first = tokens[index..<(index + phraseLength)].map { Self.bareWord($0).lowercased() }
                let second = tokens[(index + phraseLength)..<(index + (phraseLength * 2))].map { Self.bareWord($0).lowercased() }
                if first == second {
                    let removed = tokens[index..<(index + phraseLength)].joined(separator: " ")
                    tokens.removeSubrange(index..<(index + phraseLength))
                    edits.append(SpeechRepairEdit(kind: .repetitionRemoval, original: removed, replacement: ""))
                } else {
                    index += 1
                }
            }
            phraseLength -= 1
        }
        return tokens.joined(separator: " ")
    }

    private func replacementTargetIndex(before markerIndex: Int, replacementToken: String, tokens: [String]) -> Int? {
        let replacementKind = Self.semanticKind(of: replacementToken)
        let lowerBound = max(markerIndex - 6, 0)
        for index in stride(from: markerIndex - 1, through: lowerBound, by: -1) {
            let token = Self.bareWord(tokens[index])
            guard token.isEmpty == false else { continue }
            if Self.semanticKind(of: token) == replacementKind {
                return index
            }
        }
        return markerIndex - 1
    }

    private func removeImmediateRepetitions(from text: String, edits: inout [SpeechRepairEdit]) -> String {
        var tokens = Self.tokenize(text)
        var index = 1
        while index < tokens.count {
            let previous = Self.bareWord(tokens[index - 1])
            let current = Self.bareWord(tokens[index])
            if previous.isEmpty == false,
               previous.caseInsensitiveCompare(current) == .orderedSame {
                edits.append(SpeechRepairEdit(kind: .repetitionRemoval, original: tokens[index - 1], replacement: ""))
                tokens.remove(at: index - 1)
            } else {
                index += 1
            }
        }
        return tokens.joined(separator: " ")
    }

    private func cleanPunctuation(in text: String, edits: inout [SpeechRepairEdit]) -> String {
        var output = text
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([,;:]){2,}"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #",\s*([.!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(
                of: #",\s+(about|at|to|for|with|from|on|in|of|by|into|after|before)\b"#,
                with: " $1",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let first = output.first, first.isLetter {
            output.replaceSubrange(output.startIndex...output.startIndex, with: String(first).uppercased())
        }
        if output != text {
            edits.append(SpeechRepairEdit(kind: .punctuationCleanup, original: text, replacement: output))
        }
        return output
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
    }

    private static func bareWord(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private enum SemanticKind: Equatable {
        case number
        case weekday
        case capitalized
        case word
    }

    private static func semanticKind(of token: String) -> SemanticKind {
        let bare = bareWord(token)
        let lowercased = bare.lowercased()
        let numberWords: Set<String> = [
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
            "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
            "nineteen", "twenty", "thirty", "forty", "fifty", "hundred", "thousand",
        ]
        let weekdays: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

        if Double(lowercased) != nil || numberWords.contains(lowercased) { return .number }
        if weekdays.contains(lowercased) { return .weekday }
        if bare.first?.isUppercase == true { return .capitalized }
        return .word
    }
}

struct TranscriptGroundingResult: Equatable, Sendable {
    let isGrounded: Bool
    let unsupportedTokens: Set<String>
}

struct TranscriptGroundingValidator: Sendable {
    func validate(
        candidate: String,
        sourceTranscript: String,
        allowedContext: Set<String>
    ) -> TranscriptGroundingResult {
        let contextProtected = allowedContext.reduce(into: Set<String>()) { partial, value in
            partial.formUnion(protectedTokens(in: value))
        }
        let sourceWords = sourceTranscript
            .split(whereSeparator: { $0.isLetter == false && $0.isNumber == false })
            .map { String($0).lowercased() }
        let sourceProtected = protectedTokens(in: sourceTranscript).map { $0.lowercased() }
        let allowed = Set(sourceWords)
            .union(sourceProtected)
            .union(contextProtected.map { $0.lowercased() })
        let candidateProtected = protectedTokens(in: candidate)
        let unsupported = Set(candidateProtected.filter { token in
            if allowed.contains(token.lowercased()) { return false }
            let components = identifierComponents(in: token)
            return components.isEmpty || components.allSatisfy(allowed.contains) == false
        })
        return TranscriptGroundingResult(isGrounded: unsupported.isEmpty, unsupportedTokens: unsupported)
    }

    private func protectedTokens(in text: String) -> Set<String> {
        let rawTokens = text.split(whereSeparator: { $0.isWhitespace || ",.;:!?()[]{}\"“”".contains($0) })
        return Set(rawTokens.compactMap { substring in
            let token = String(substring)
            guard token.isEmpty == false else { return nil }
            let isNumber = token.contains(where: \.isNumber)
            let isURLOrPath = token.contains("://") || token.contains("/") || token.contains("\\")
            let isIdentifier = token.contains("_") || token.dropFirst().contains(where: \.isUppercase)
            let isCapitalized = token.first?.isUppercase == true && token.count > 1
            return (isNumber || isURLOrPath || isIdentifier || isCapitalized) ? token : nil
        })
    }

    private func identifierComponents(in token: String) -> [String] {
        guard token.contains("://") == false,
              token.contains("/") == false,
              token.contains("\\") == false,
              token.contains(where: \.isNumber) == false,
              token.contains("_") || token.contains("-") || token.dropFirst().contains(where: \.isUppercase)
        else { return [] }
        let separated = token
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"([a-z])([A-Z])"#, with: "$1 $2", options: .regularExpression)
        return separated
            .split(whereSeparator: { $0.isLetter == false && $0.isNumber == false })
            .map { String($0).lowercased() }
    }
}
