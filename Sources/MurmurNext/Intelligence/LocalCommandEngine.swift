import Foundation

enum TextTransformAction: Equatable, Sendable {
    case replace(String)
    case insert(String)
    case pressEnter
}

enum TextTransformError: Error, LocalizedError {
    case selectionRequired
    case requiresLocalLanguageModel
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .selectionRequired: "Select text before using this command."
        case .requiresLocalLanguageModel: "This command requires a verified local cleanup model."
        case .emptyResult: "The local command did not produce safe replacement text."
        }
    }
}

protocol LocalTextTransformEngine: Sendable {
    func apply(command: String, selectedText: String?) async throws -> TextTransformAction
}

struct HeuristicTextTransformEngine: LocalTextTransformEngine {
    func apply(command: String, selectedText: String?) async throws -> TextTransformAction {
        let normalized = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "press enter" || normalized == "hit enter" || normalized == "send this" {
            return .pressEnter
        }

        guard let selectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              selectedText.isEmpty == false
        else { throw TextTransformError.selectionRequired }

        if normalized.contains("uppercase") || normalized.contains("upper case") {
            return .replace(selectedText.uppercased())
        }
        if normalized.contains("lowercase") || normalized.contains("lower case") {
            return .replace(selectedText.lowercased())
        }
        if normalized.contains("title case") || normalized.contains("capitalize") {
            return .replace(selectedText.capitalized)
        }
        if normalized.contains("bullet") {
            let items = selectedText
                .replacingOccurrences(of: #"\s+and\s+"#, with: ", ", options: [.regularExpression, .caseInsensitive])
                .split(whereSeparator: { ",;\n".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .map { "• \(capitalize($0))" }
            guard items.isEmpty == false else { throw TextTransformError.emptyResult }
            return .replace(items.joined(separator: "\n"))
        }
        if normalized.contains("concise") || normalized.contains("shorter") {
            var result = selectedText
            let removals = [
                #"(?i)\bI think that\s+"#,
                #"(?i)\bI think\s+"#,
                #"(?i)\breally\s+"#,
                #"(?i)\bvery\s+"#,
                #"(?i)\bbasically\s+"#,
                #"(?i)\bjust\s+"#,
            ]
            for pattern in removals {
                result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
            result = result
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = result.first, first.isLetter {
                result.replaceSubrange(result.startIndex...result.startIndex, with: String(first).uppercased())
            }
            return .replace(result)
        }

        throw TextTransformError.requiresLocalLanguageModel
    }

    private func capitalize(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }
}
