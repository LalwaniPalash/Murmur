import Foundation
import Testing
@testable import MurmurNext

struct TranscriptPipelineTests {
    @Test func appliesDictionaryTermsAsWholePhrases() {
        let dictionary = [
            DictionaryItem(id: UUID(), spokenForm: "super base", writtenForm: "Supabase", context: .code, createdAt: Date()),
            DictionaryItem(id: UUID(), spokenForm: "ver cell", writtenForm: "Vercel", context: nil, createdAt: Date()),
        ]
        let processor = TranscriptPersonalizer(dictionary: dictionary, snippets: [])

        #expect(processor.apply(to: "Deploy super base on ver cell.", context: .code).text == "Deploy Supabase on Vercel.")
        #expect(processor.apply(to: "A super baseline.", context: .code).text == "A super baseline.")
        #expect(processor.apply(to: "Deploy super base.", context: .email).text == "Deploy super base.")
    }

    @Test func expandsSnippetTriggersInsideNaturalSentences() {
        let snippets = [
            SnippetItem(id: UUID(), trigger: "my meeting link", expansion: "https://cal.example/murmur", createdAt: Date()),
        ]
        let processor = TranscriptPersonalizer(dictionary: [], snippets: snippets)

        let result = processor.apply(to: "Please use my meeting link to book a time.", context: .email)
        #expect(result.text == "Please use https://cal.example/murmur to book a time.")
        #expect(result.allowedGroundingContext == ["https://cal.example/murmur"])
    }

    @Test func convertsSpokenPunctuationAndParagraphs() {
        let result = TranscriptPersonalizer(dictionary: [], snippets: []).apply(
            to: "Hello comma this is quiet period new paragraph Thank you exclamation mark",
            context: .document
        )
        #expect(result.text == "Hello, this is quiet.\n\nThank you!")
    }

    @Test func formatsSpokenNumberedListsWithoutChangingTheItems() {
        let result = TranscriptPersonalizer(dictionary: [], snippets: []).apply(
            to: "one apples two bananas three oranges",
            context: .document
        )
        #expect(result.text == "1. Apples\n2. Bananas\n3. Oranges")
    }

    @Test func finalPipelineRepairsBeforePersonalizingAndValidatesGrounding() throws {
        let dictionary = [
            DictionaryItem(id: UUID(), spokenForm: "murmur flow", writtenForm: "Murmur Flow", context: nil, createdAt: Date()),
        ]
        let pipeline = FinalTranscriptPipeline(
            repairEngine: SpeechRepairEngine(),
            personalizer: TranscriptPersonalizer(dictionary: dictionary, snippets: [])
        )

        let result = try pipeline.finalize(
            "Email John, I mean Jane, about murmur flow.",
            context: .email
        )
        #expect(result.text == "Email Jane about Murmur Flow.")
        #expect(result.repairEdits.isEmpty == false)
    }

    @Test func polishedCleanupAddsSafeSentenceCasingAndTerminalPunctuation() throws {
        let pipeline = FinalTranscriptPipeline(
            repairEngine: SpeechRepairEngine(),
            personalizer: TranscriptPersonalizer(dictionary: [], snippets: []),
            removeSpeechArtifacts: false,
            cleanupIntensity: .polished
        )

        #expect(try pipeline.finalize("send the update", context: .email).text == "Send the update.")
        #expect(try pipeline.finalize("git status", context: .terminal).text == "git status")
    }

    @Test func developerFormattingPreservesSpokenSymbolsAndNamingConventions() {
        let processor = TranscriptPersonalizer(dictionary: [], snippets: [])
        #expect(
            processor.apply(
                to: "let camel case user profile equals open quote quiet user close quote",
                context: .code
            ).text == "let userProfile = \"quiet user\""
        )
        #expect(
            processor.apply(
                to: "git checkout dash b snake case feature name",
                context: .terminal
            ).text == "git checkout - b feature_name"
        )
        #expect(
            processor.apply(to: "open parenthesis hello close parenthesis", context: .email).text
                == "open parenthesis hello close parenthesis"
        )
    }

    @Test func groundedPipelineAllowsIdentifiersComposedOnlyFromSpokenWords() throws {
        let pipeline = FinalTranscriptPipeline(
            repairEngine: SpeechRepairEngine(),
            personalizer: TranscriptPersonalizer(dictionary: [], snippets: [])
        )
        let result = try pipeline.finalize(
            "let camel case user profile equals account",
            context: .code
        )
        #expect(result.text == "let userProfile = account")
    }
}
