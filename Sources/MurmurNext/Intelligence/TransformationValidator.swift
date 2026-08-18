import Foundation

enum TransformationValidationFailure: Error, Equatable, Sendable {
    case empty
    case oversized
    case instructionLeakage
    case implausibleLength
    case protectedDetailMissing(String)
    case protectedDetailInvented(String)
}

struct TransformationValidationOutcome: Equatable, Sendable {
    let failure: TransformationValidationFailure?

    var isValid: Bool { failure == nil }

    static let valid = TransformationValidationOutcome(failure: nil)
}

struct TransformationValidator: Sendable {
    private static let maximumCharacters = 40_000
    private static let leakagePrefixes = [
        "here is the revised",
        "here's the revised",
        "revised email:",
        "rewritten text:",
        "output:",
        "```",
    ]
    private static let commonCapitalizedWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "august", "by", "can", "could",
        "dear", "december", "february", "friday", "hello", "hi", "i", "in",
        "january", "july", "june", "march", "may", "monday", "november", "october",
        "on", "our", "please", "saturday", "september", "sunday", "thank", "thanks",
        "the", "this", "thursday", "tomorrow", "tuesday", "we", "wednesday", "will",
        "would", "you", "your",
    ]

    func validate(
        candidate: String,
        source: String,
        operation: WritingTransformationOperation,
        protectedTerms: Set<String> = []
    ) -> TransformationValidationOutcome {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.isEmpty == false else { return .init(failure: .empty) }
        guard candidate.count <= Self.maximumCharacters else { return .init(failure: .oversized) }

        let lowercaseCandidate = candidate.lowercased()
        if Self.leakagePrefixes.contains(where: { lowercaseCandidate.hasPrefix($0) }) {
            return .init(failure: .instructionLeakage)
        }

        guard lengthIsPlausible(candidate: candidate, source: source, operation: operation) else {
            return .init(failure: .implausibleLength)
        }

        let sourceHighRisk = highRiskDetails(in: source)
        let candidateHighRisk = highRiskDetails(in: candidate)
        if let invented = firstCountMismatch(excessIn: candidateHighRisk, comparedWith: sourceHighRisk) {
            return .init(failure: .protectedDetailInvented(invented))
        }
        if let missing = firstCountMismatch(excessIn: sourceHighRisk, comparedWith: candidateHighRisk) {
            return .init(failure: .protectedDetailMissing(missing))
        }

        let requiredTerms = protectedSourceTerms(in: source, explicit: protectedTerms)
        let candidateTerms = exactCounts(requiredTerms.map(\.value), in: candidate)
        for term in requiredTerms.sorted(by: { $0.value.localizedStandardCompare($1.value) == .orderedAscending }) {
            if candidateTerms[term.value, default: 0] < term.count {
                return .init(failure: .protectedDetailMissing(term.value))
            }
        }

        return .valid
    }

    private func lengthIsPlausible(
        candidate: String,
        source: String,
        operation: WritingTransformationOperation
    ) -> Bool {
        guard source.isEmpty == false else { return true }
        let ratio = Double(candidate.count) / Double(source.count)
        switch operation {
        case .professionalEmail:
            return ratio >= 0.45 && ratio <= 2.0
        case .semanticCommand:
            return ratio >= 0.10 && ratio <= 3.0
        }
    }

    private func highRiskDetails(in text: String) -> [String: Int] {
        let patterns = [
            #"(?i)\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#,
            #"(?i)\b(?:https?://|www\.)[^\s<>()]+"#,
            #"(?<![\p{L}])(?:[$€£₹]\s*)?\d(?:[\d,./:\-]*\d)?%?"#,
        ]
        var values: [String] = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                var value = String(text[range])
                if pattern.contains("https?") {
                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
                }
                values.append(value)
            }
        }
        return counts(values)
    }

    private func protectedSourceTerms(
        in source: String,
        explicit: Set<String>
    ) -> [(value: String, count: Int)] {
        var terms = explicit.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        if let expression = try? NSRegularExpression(pattern: #"\b[\p{Lu}][\p{L}\p{N}_\-]{2,}\b"#) {
            for match in expression.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range, in: source) else { continue }
                let value = String(source[range])
                if Self.commonCapitalizedWords.contains(value.lowercased()) == false {
                    terms.insert(value)
                }
            }
        }
        let values = terms.sorted()
        let occurrences = exactCounts(values, in: source)
        return values.compactMap { value in
            guard occurrences[value, default: 0] > 0 else { return nil }
            return (value, occurrences[value, default: 0])
        }
    }

    private func exactCounts(_ terms: [String], in text: String) -> [String: Int] {
        var result: [String: Int] = [:]
        for term in terms {
            let pattern = "(?<![\\p{L}\\p{N}_])\(NSRegularExpression.escapedPattern(for: term))(?![\\p{L}\\p{N}_])"
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            result[term] = expression.numberOfMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text)
            )
        }
        return result
    }

    private func counts(_ values: [String]) -> [String: Int] {
        Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
    }

    private func firstCountMismatch(
        excessIn lhs: [String: Int],
        comparedWith rhs: [String: Int]
    ) -> String? {
        lhs.keys.sorted().first { lhs[$0, default: 0] > rhs[$0, default: 0] }
    }
}
