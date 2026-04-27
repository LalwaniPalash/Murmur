import AppKit
import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.murmur.app", category: "Transform")

struct TransformResult: Sendable {
    let text: String
    let usedFallback: Bool
    let fallbackReason: String?

    static func direct(_ text: String) -> TransformResult {
        .init(text: text, usedFallback: false, fallbackReason: nil)
    }

    static func fallback(_ text: String, reason: String) -> TransformResult {
        .init(text: text, usedFallback: true, fallbackReason: reason)
    }
}

@MainActor
protocol TransformEngine {
    func cleanup(
        text: String,
        level: CleanupLevel,
        context: AppWritingContext,
        styleProfile: StyleProfile?
    ) async -> TransformResult
    func applyCommand(
        command: String,
        to selectedText: String,
        context: AppWritingContext
    ) async -> TransformResult
}

final class AppContextClassifier {
    func currentApp() -> FrontmostAppDescriptor {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier ?? "unknown.bundle"
        let name = app?.localizedName ?? "Unknown App"
        return FrontmostAppDescriptor(
            localizedName: name,
            bundleIdentifier: bundleID,
            writingContext: classify(bundleIdentifier: bundleID, localizedName: name)
        )
    }

    func classify(bundleIdentifier: String, localizedName: String) -> AppWritingContext {
        let fingerprint = "\(bundleIdentifier.lowercased()) \(localizedName.lowercased())"
        if fingerprint.contains("terminal") || fingerprint.contains("iterm") || fingerprint.contains("warp") || fingerprint.contains("kitty") {
            return .terminal
        }
        if fingerprint.contains("cursor") || fingerprint.contains("windsurf") || fingerprint.contains("xcode") || fingerprint.contains(" code") {
            return .code
        }
        if fingerprint.contains("mail") || fingerprint.contains("outlook") || fingerprint.contains("superhuman") {
            return .email
        }
        if fingerprint.contains("messages") || fingerprint.contains("slack") || fingerprint.contains("discord") || fingerprint.contains("chat") {
            return .chat
        }
        if fingerprint.contains("safari") || fingerprint.contains("chrome") || fingerprint.contains("arc") || fingerprint.contains("firefox") {
            return .browserForm
        }
        if fingerprint.contains("notes") || fingerprint.contains("pages") || fingerprint.contains("word") || fingerprint.contains("textedit") {
            return .document
        }
        return .unknown
    }
}

struct FormatterPipeline {
    func format(
        transcript: String,
        context: AppWritingContext,
        cleanupLevel: CleanupLevel,
        personalization: PersonalizationSnapshot
    ) -> String {
        var working = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return working }

        if let snippet = personalization.matchingSnippet(for: working) {
            return snippet.expansion
        }
        working = applyDictionary(to: working, context: context, personalization: personalization)
        working = applyPunctuationCommands(to: working, context: context)
        working = applyBacktrackRules(to: working)
        if context == .code || context == .terminal {
            working = applyDeveloperLexicon(to: working)
        }
        if cleanupLevel != .off && context != .code && context != .terminal {
            working = normalizeWhitespace(in: working)
            working = capitalizeSentenceIfNeeded(working)
        }
        return working
    }
    private func applyDictionary(to text: String, context: AppWritingContext, personalization: PersonalizationSnapshot) -> String {
        personalization.dictionaryEntries.reduce(text) { partial, entry in
            guard entry.context == nil || entry.context == context else {
                return partial
            }
            return partial.replacingOccurrences(
                of: entry.phrase,
                with: entry.replacement,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }
    }

    private func applyPunctuationCommands(to text: String, context: AppWritingContext) -> String {
        var output = text
        let replacements: [(String, String)] = [
            (" comma", ","),
            (" period", "."),
            (" full stop", "."),
            (" question mark", "?"),
            (" exclamation mark", "!"),
            (" semicolon", ";"),
            (" colon", ":"),
            (" open parenthesis", " ("),
            (" close parenthesis", ") "),
            (" new line", "\n"),
            (" new paragraph", "\n\n"),
        ]

        for (spoken, symbol) in replacements {
            output = output.replacingOccurrences(of: spoken, with: symbol, options: [.caseInsensitive])
        }

        if context == .code || context == .terminal {
            let developerReplacements: [(String, String)] = [
                (" dot ", "."),
                (" slash ", "/"),
                (" backslash ", "\\"),
                (" underscore ", "_"),
                (" dash ", "-"),
                (" open brace", " {"),
                (" close brace", "} "),
                (" open bracket", " ["),
                (" close bracket", "] "),
            ]
            for (spoken, symbol) in developerReplacements {
                output = output.replacingOccurrences(of: spoken, with: symbol, options: [.caseInsensitive])
            }
        }

        return output
    }

    private func applyBacktrackRules(to text: String) -> String {
        let patterns = [
            #"(?i)\bactually\b"#,
            #"(?i)\bcorrection\b"#,
        ]
        return patterns.reduce(text) { partial, pattern in
            partial.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
    }

    private func applyDeveloperLexicon(to text: String) -> String {
        var output = text
        let replacements: [(String, String)] = [
            ("snake case", "snake_case"),
            ("camel case", "camelCase"),
            ("pascal case", "PascalCase"),
            ("dot env", ".env"),
            ("read me", "README"),
            ("git ignore", ".gitignore"),
            ("open ai", "OpenAI"),
        ]
        for (spoken, replacement) in replacements {
            output = output.replacingOccurrences(of: spoken, with: replacement, options: [.caseInsensitive])
        }
        return output
    }

    private func normalizeWhitespace(in text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " ,", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capitalizeSentenceIfNeeded(_ text: String) -> String {
        guard let first = text.first else { return text }
        if text.contains("://") || text.hasPrefix(".") || text.hasPrefix("@") {
            return text
        }
        return String(first).uppercased() + text.dropFirst()
    }
}

final class HybridTransformEngine: TransformEngine {
    private let heuristic = HeuristicTransformEngine()
    private let modelManager: ModelManager?
    private let settingsStore: SettingsStore?

    init(modelManager: ModelManager? = nil, settingsStore: SettingsStore? = nil) {
        self.modelManager = modelManager
        self.settingsStore = settingsStore
    }

    func cleanup(
        text: String,
        level: CleanupLevel,
        context: AppWritingContext,
        styleProfile: StyleProfile?
    ) async -> TransformResult {
        guard level != .off else {
            return .direct(text)
        }

        if let transformed = await askLlamaCLI(
            task: .cleanup(text: text, level: level, context: context, styleProfile: styleProfile)
        ) {
            return .direct(transformed)
        }

        if level == .light {
            let result = await heuristic.cleanup(text: text, level: level, context: context, styleProfile: styleProfile)
            return .direct(result.text)
        }

        if context == .code || context == .terminal {
            let result = await heuristic.cleanup(text: text, level: level, context: context, styleProfile: styleProfile)
            return .fallback(result.text, reason: "Code-safe local AI model unavailable")
        }

#if canImport(FoundationModels)
        if #available(macOS 26.0, *), context != .code, context != .terminal {
            if let transformed = await askFoundationModel(
                prompt: """
                Rewrite this dictated text with \(level.rawValue) cleanup.
                Preserve the meaning.
                Context: \(context.rawValue).
                Style: \(styleProfile?.instructions ?? "Keep the original voice.")
                Text: \(text)
                """
            ) {
                return .direct(transformed)
            }
        }
#endif

        let result = await heuristic.cleanup(text: text, level: level, context: context, styleProfile: styleProfile)
        return .fallback(result.text, reason: "Local AI model unavailable")
    }

    func applyCommand(
        command: String,
        to selectedText: String,
        context: AppWritingContext
    ) async -> TransformResult {
        let lowercasedCommand = command.lowercased()

        if let transformed = await askLlamaCLI(
            task: .command(command: command, selectedText: selectedText, context: context)
        ) {
            return .direct(transformed)
        }

        if lowercasedCommand.contains("summarize")
            || lowercasedCommand.contains("concise")
            || lowercasedCommand.contains("bullet")
            || lowercasedCommand.contains("uppercase")
            || lowercasedCommand.contains("lowercase")
            || context == .code
            || context == .terminal {
            let result = await heuristic.applyCommand(command: command, to: selectedText, context: context)
            return .fallback(result.text, reason: "Local AI model unavailable")
        }

#if canImport(FoundationModels)
        if #available(macOS 26.0, *), context != .code, context != .terminal {
            if let transformed = await askFoundationModel(
                prompt: """
                Apply the following editing instruction to the selected text.
                Instruction: \(command)
                Context: \(context.rawValue)
                Selected text:
                \(selectedText)
                """
            ) {
                return .direct(transformed)
            }
        }
#endif

        let result = await heuristic.applyCommand(command: command, to: selectedText, context: context)
        return .fallback(result.text, reason: "Local AI model unavailable")
    }

    private func askLlamaCLI(task: LlamaTask) async -> String? {
        guard let modelManager, let settingsStore else {
            return nil
        }

        guard let runtimePath = modelManager.runtimes.first(where: { $0.kind == .llamaCPP && $0.installState == .installed })?.installPath,
              let selectedModel = modelManager.preferredLlamaModel(using: settingsStore.snapshot),
              let modelPath = selectedModel.storagePath
        else {
            return nil
        }

        if task.context.requiresCodeSafeModel,
           selectedModel.modelIdentifier != LlamaModelPreset.qwen25Coder_05b_q8.rawValue {
            return nil
        }

        let promptFiles = makePromptFiles(for: task)
        guard let promptFiles else {
            return nil
        }

        defer {
            try? FileManager.default.removeItem(at: promptFiles.systemPromptURL)
            try? FileManager.default.removeItem(at: promptFiles.userPromptURL)
        }

        return await Task.detached(priority: .userInitiated) {
            do {
                let output = try CLIProcessRunner.run(
                    executablePath: runtimePath,
                    arguments: [
                        "-m", modelPath,
                        "--log-disable",
                        "--no-display-prompt",
                        "--conversation",
                        "--single-turn",
                        "--system-prompt-file", promptFiles.systemPromptURL.path,
                        "--file", promptFiles.userPromptURL.path,
                        "--temp", "0.2",
                        "--top-p", "0.9",
                        "--seed", "42",
                        "-n", task.maxGeneratedTokens,
                        "-c", "4096",
                        "-fa"
                    ],
                    timeout: task.timeout
                )
                return Self.sanitizeLlamaOutput(output)
            } catch {
                logger.error("llama-cli failed: \(error.localizedDescription)")
                return nil
            }
        }.value
    }

    private func makePromptFiles(for task: LlamaTask) -> (systemPromptURL: URL, userPromptURL: URL)? {
        let systemPrompt = """
        You are Murmur, a fully local text transformation engine inside a dictation app.
        Return the final transformed text only between these exact delimiter lines:
        <murmur-output>
        </murmur-output>
        Do not add explanations, markdown fences, labels, or commentary.
        Do not add suggested next actions, follow-up prompts, buttons, or UI copy.
        Preserve the user's meaning exactly unless the instruction asks for a change.
        """

        let userPrompt: String
        switch task {
        case .cleanup(let text, let level, let context, let styleProfile):
            userPrompt = """
            Task: Clean up dictated text.
            Cleanup level: \(level.rawValue)
            Context: \(context.rawValue)
            Style: \(styleProfile?.instructions ?? "Preserve the original voice.")
            Output requirements: keep the same meaning, remove filler and formatting noise, and return only the cleaned text between the required delimiter lines.

            Text:
            \(text)
            """
        case .command(let command, let selectedText, let context):
            userPrompt = """
            Task: Apply the user's editing instruction to the selected text.
            Context: \(context.rawValue)
            Instruction:
            \(command)

            Selected text:
            \(selectedText)
            """
        }

        let base = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-llama-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let systemPromptURL = base.appendingPathComponent("system.txt")
            let userPromptURL = base.appendingPathComponent("prompt.txt")
            try systemPrompt.write(to: systemPromptURL, atomically: true, encoding: .utf8)
            try userPrompt.write(to: userPromptURL, atomically: true, encoding: .utf8)
            return (systemPromptURL, userPromptURL)
        } catch {
            return nil
        }
    }

    nonisolated static func sanitizeLlamaOutput(_ output: String) -> String? {
        let sanitized = output
            .replacingOccurrences(of: "<eos>", with: "")
            .replacingOccurrences(of: "<end_of_turn>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let delimited = extractDelimitedOutput(from: sanitized) {
            return delimited.nonEmpty
        }

        // New prompts require delimiters. Treat unstructured model output as untrusted so
        // assistant UI text, actions, or commentary cannot be inserted into the user's app.
        if sanitized.contains("<murmur-output>") || sanitized.contains("</murmur-output>") {
            return nil
        }

        return nil
    }

    private nonisolated static func extractDelimitedOutput(from output: String) -> String? {
        guard let startRange = output.range(of: "<murmur-output>", options: [.caseInsensitive]),
              let endRange = output.range(
                of: "</murmur-output>",
                options: [.caseInsensitive],
                range: startRange.upperBound..<output.endIndex
              ) else {
            return nil
        }

        var sanitized = String(output[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let artifactPatterns = [
            #"(?im)^\s*Ask for follow-up changes\s*$"#,
            #"(?im)\s+Ask for follow-up changes\s*$"#,
            #"(?im)^\s*Follow-up changes\s*$"#,
            #"(?im)\s+Follow-up changes\s*$"#
        ]

        for pattern in artifactPatterns {
            sanitized = sanitized.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return sanitized
    }

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func askFoundationModel(prompt: String) async -> String? {
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        } catch {
            return nil
        }
    }
#endif
}

private enum LlamaTask {
    case cleanup(text: String, level: CleanupLevel, context: AppWritingContext, styleProfile: StyleProfile?)
    case command(command: String, selectedText: String, context: AppWritingContext)

    var context: AppWritingContext {
        switch self {
        case .cleanup(_, _, let context, _), .command(_, _, let context):
            context
        }
    }

    var maxGeneratedTokens: String {
        switch self {
        case .cleanup:
            "384"
        case .command:
            "512"
        }
    }

    var timeout: TimeInterval {
        switch self {
        case .cleanup:
            120
        case .command:
            180
        }
    }
}

private struct HeuristicTransformEngine: TransformEngine {
    func cleanup(
        text: String,
        level: CleanupLevel,
        context: AppWritingContext,
        styleProfile: StyleProfile?
    ) async -> TransformResult {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return .direct(output) }

        if level == .light || level == .medium || level == .heavy {
            let fillers = [" uh ", " um ", " like ", " you know "]
            for filler in fillers {
                output = output.replacingOccurrences(of: filler, with: " ", options: [.caseInsensitive])
            }
        }

        output = output.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if context != .code && context != .terminal, let first = output.first {
            output = String(first).uppercased() + output.dropFirst()
            if !output.hasSuffix(".") && !output.hasSuffix("?") && !output.hasSuffix("!") {
                output.append(".")
            }
        }

        if level == .heavy, let styleProfile {
            output += " \(styleProfile.instructions)"
        }

        return .direct(output)
    }

    func applyCommand(command: String, to selectedText: String, context: AppWritingContext) async -> TransformResult {
        let lowercasedCommand = command.lowercased()
        if lowercasedCommand.contains("summarize") {
            let result = selectedText
                .split(separator: ".")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(2)
                .joined(separator: ". ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty ?? selectedText
            return .direct(result)
        }
        if lowercasedCommand.contains("concise") {
            let result = selectedText
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .split(separator: " ")
                .prefix(30)
                .joined(separator: " ")
            return .direct(result)
        }
        if lowercasedCommand.contains("bullet") {
            let result = selectedText
                .split(separator: ",")
                .map { "- \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
                .joined(separator: "\n")
            return .direct(result)
        }
        if lowercasedCommand.contains("uppercase") {
            return .direct(selectedText.uppercased())
        }
        if lowercasedCommand.contains("lowercase") {
            return .direct(selectedText.lowercased())
        }
        if context == .code || context == .terminal {
            return .direct(selectedText)
        }
        return .direct(selectedText)
    }
}

private extension PersonalizationSnapshot {
    func matchingSnippet(for text: String) -> Snippet? {
        snippets.first { snippet in
            snippet.trigger.compare(text.trimmingCharacters(in: .whitespacesAndNewlines), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}

private extension AppWritingContext {
    var requiresCodeSafeModel: Bool {
        self == .code || self == .terminal
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
