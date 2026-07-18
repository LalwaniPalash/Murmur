import Foundation

struct TranscriptPersonalizationResult: Equatable, Sendable {
    let text: String
    let allowedGroundingContext: Set<String>
}

struct TranscriptPersonalizer: Sendable {
    let dictionary: [DictionaryItem]
    let snippets: [SnippetItem]

    func apply(to transcript: String, context: WritingContext) -> TranscriptPersonalizationResult {
        var text = transcript
        var allowedContext = Set<String>()

        for snippet in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let replacement = replaceWholePhrase(snippet.trigger, with: snippet.expansion, in: text)
            if replacement != text {
                text = replacement
                allowedContext.insert(snippet.expansion)
            }
        }

        for item in dictionary
            .filter({ $0.context == nil || $0.context == context })
            .sorted(by: { $0.spokenForm.count > $1.spokenForm.count }) {
            let replacement = replaceWholePhrase(item.spokenForm, with: item.writtenForm, in: text)
            if replacement != text {
                text = replacement
                allowedContext.insert(item.writtenForm)
            }
        }

        text = applyPunctuationCommands(to: text)
        if context == .code || context == .terminal {
            text = applyDeveloperFormatting(to: text)
        }
        text = formatNumberedListIfPresent(text)
        text = cleanSpacing(text)
        return TranscriptPersonalizationResult(text: text, allowedGroundingContext: allowedContext)
    }

    private func replaceWholePhrase(_ phrase: String, with replacement: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: phrase.trimmingCharacters(in: .whitespacesAndNewlines))
        guard escaped.isEmpty == false,
              let expression = try? NSRegularExpression(pattern: "(?i)(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])")
        else { return text }
        return expression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    private func applyPunctuationCommands(to text: String) -> String {
        var output = text
        let commands: [(String, String)] = [
            ("new paragraph", "\n\n"),
            ("new line", "\n"),
            ("question mark", "?"),
            ("exclamation mark", "!"),
            ("full stop", "."),
            ("period", "."),
            ("semicolon", ";"),
            ("colon", ":"),
            ("comma", ","),
        ]
        for (command, punctuation) in commands {
            output = replaceWholePhrase(command, with: punctuation, in: output)
        }
        return output
    }

    private func formatNumberedListIfPresent(_ text: String) -> String {
        let pattern = #"(?i)^\s*(?:one|1)\s+(.+?)\s+(?:two|2)\s+(.+?)\s+(?:three|3)\s+(.+?)[.!?]?\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 4,
              let firstRange = Range(match.range(at: 1), in: text),
              let secondRange = Range(match.range(at: 2), in: text),
              let thirdRange = Range(match.range(at: 3), in: text)
        else { return text }

        let items = [String(text[firstRange]), String(text[secondRange]), String(text[thirdRange])]
        return items.enumerated().map { index, item in
            "\(index + 1). \(capitalize(item.trimmingCharacters(in: .whitespacesAndNewlines)))"
        }.joined(separator: "\n")
    }

    private func applyDeveloperFormatting(to text: String) -> String {
        var output = applyNamingConvention("camel case", separator: "", capitalizeFollowing: true, to: text)
        output = applyNamingConvention("snake case", separator: "_", capitalizeFollowing: false, to: output)
        output = applyNamingConvention("kebab case", separator: "-", capitalizeFollowing: false, to: output)

        let symbols: [(String, String)] = [
            ("open parenthesis", "("), ("close parenthesis", ")"),
            ("open bracket", "["), ("close bracket", "]"),
            ("open brace", "{"), ("close brace", "}"),
            ("double quote", "\""), ("open quote", "\""), ("close quote", "\""),
            ("single quote", "'"), ("underscore", "_"),
            ("forward slash", "/"), ("backslash", "\\"),
            ("equals", "="), ("dash", "-"), ("dot", "."),
        ]
        for (phrase, symbol) in symbols {
            output = replaceWholePhrase(phrase, with: symbol, in: output)
        }
        return output
            .replacingOccurrences(of: #"\s+([\)\]\}.,_/])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([\(\[\{_/])\s+"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s*=\s*"#, with: " = ", options: .regularExpression)
            .replacingOccurrences(of: #"\"\s*([^\"]*?)\s*\""#, with: "\"$1\"", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyNamingConvention(
        _ command: String,
        separator: String,
        capitalizeFollowing: Bool,
        to text: String
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: command)
        let pattern = "(?i)\\b\(escaped)\\s+((?:[a-zA-Z0-9]+(?:\\s+|$)){1,6}?)(?=\\s*(?:equals|comma|period|dash|open|close|$))"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        var output = text
        for match in expression.matches(in: output, range: NSRange(output.startIndex..., in: output)).reversed() {
            guard let fullRange = Range(match.range(at: 0), in: output),
                  let wordsRange = Range(match.range(at: 1), in: output)
            else { continue }
            let words = output[wordsRange].split(whereSeparator: \.isWhitespace).map(String.init)
            guard let first = words.first else { continue }
            let replacement: String
            if capitalizeFollowing {
                replacement = first.lowercased() + words.dropFirst().map { word in
                    word.prefix(1).uppercased() + word.dropFirst().lowercased()
                }.joined()
            } else {
                replacement = words.map { $0.lowercased() }.joined(separator: separator)
            }
            let suffix = fullRange.upperBound < output.endIndex ? " " : ""
            output.replaceSubrange(fullRange, with: replacement + suffix)
        }
        return output
    }

    private func cleanSpacing(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[ \t]+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capitalize(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }
}

struct FinalTranscript: Equatable, Sendable {
    let text: String
    let repairEdits: [SpeechRepairEdit]
}

enum FinalTranscriptPipelineError: Error, LocalizedError {
    case empty
    case ungrounded(Set<String>)

    var errorDescription: String? {
        switch self {
        case .empty: "Murmur did not hear enough speech to write safely."
        case .ungrounded: "The corrected transcript could not be verified against what was spoken."
        }
    }
}

struct FinalTranscriptPipeline: Sendable {
    let repairEngine: SpeechRepairEngine
    let personalizer: TranscriptPersonalizer
    var removeSpeechArtifacts = true
    var cleanupIntensity: CleanupIntensity = .balanced
    private let groundingValidator = TranscriptGroundingValidator()

    func finalize(_ sourceTranscript: String, context: WritingContext) throws -> FinalTranscript {
        let repaired = removeSpeechArtifacts
            ? repairEngine.repair(sourceTranscript)
            : SpeechRepairResult(text: sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines), edits: [])
        guard repaired.text.isEmpty == false else { throw FinalTranscriptPipelineError.empty }
        let personalized = personalizer.apply(to: repaired.text, context: context)
        let finalizedText = polish(personalized.text, context: context, sourceTranscript: sourceTranscript)
        guard finalizedText.isEmpty == false else { throw FinalTranscriptPipelineError.empty }
        let grounding = groundingValidator.validate(
            candidate: finalizedText,
            sourceTranscript: sourceTranscript,
            allowedContext: personalized.allowedGroundingContext
        )
        guard grounding.isGrounded else {
            throw FinalTranscriptPipelineError.ungrounded(grounding.unsupportedTokens)
        }
        return FinalTranscript(text: finalizedText, repairEdits: repaired.edits)
    }

    private func polish(_ text: String, context: WritingContext, sourceTranscript: String) -> String {
        var output = text
        if context == .code || context == .terminal {
            if sourceTranscript.first?.isLowercase == true,
               output.first?.isUppercase == true,
               let first = output.first {
                output.replaceSubrange(output.startIndex...output.startIndex, with: String(first).lowercased())
            }
            return output
        }
        guard cleanupIntensity == .polished else { return output }
        if let first = output.first, first.isLetter {
            output.replaceSubrange(output.startIndex...output.startIndex, with: String(first).uppercased())
        }
        if let last = output.last, ".!?".contains(last) == false {
            output.append(".")
        }
        return output
    }
}
