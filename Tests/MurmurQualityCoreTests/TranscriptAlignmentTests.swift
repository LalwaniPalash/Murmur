import Testing

@testable import MurmurQualityCore

struct TranscriptAlignmentTests {
    @Test func punctuationAndCaseDoNotCreateErrors() {
        let result = TranscriptAligner.align(
            expected: "Hello, Quiet World!",
            actual: "hello quiet world"
        )

        #expect(result.operations.allSatisfy { $0.kind == .match })
        #expect(result.wordErrorRate == 0)
        #expect(result.characterErrorRate == 0)
    }

    @Test func reportsSubstitutionsInsertionsAndDeletions() {
        let result = TranscriptAligner.align(
            expected: "alpha remove beta change gamma delta",
            actual: "alpha beta altered gamma insert delta"
        )

        #expect(result.operations.contains(where: { $0.kind == .substitution }))
        #expect(result.operations.contains(where: { $0.kind == .deletion }))
        #expect(result.operations.contains(where: { $0.kind == .insertion }))
        #expect(result.wordErrorRate > 0)
    }

    @Test func catchesFluentMiddleOmissionWithRequiredRegion() {
        let expected = "Opening words are present. The confidential middle section is essential. Closing words are present."
        let actual = "Opening words are present. Closing words are present."
        let result = TranscriptCompletenessAnalyzer.analyze(
            expected: expected,
            actual: actual,
            requiredPhrases: [
                RequiredPhrase(text: "Opening words", region: .beginning),
                RequiredPhrase(text: "confidential middle section", region: .middle),
                RequiredPhrase(text: "Closing words", region: .end),
            ],
            protectedTokens: []
        )

        #expect(result.isComplete == false)
        #expect(result.reasons.contains(.missingRequiredPhrase(
            RequiredPhrase(text: "confidential middle section", region: .middle)
        )))
        #expect(result.longestMissingSourceSpan?.text.contains("confidential middle section") == true)
    }

    @Test func catchesBeginningAndEndingOmissionsSeparately() {
        let expected = "Alpha opening. Beta middle. Gamma ending."
        let phrases = [
            RequiredPhrase(text: "Alpha opening", region: .beginning),
            RequiredPhrase(text: "Beta middle", region: .middle),
            RequiredPhrase(text: "Gamma ending", region: .end),
        ]

        let missingBeginning = TranscriptCompletenessAnalyzer.analyze(
            expected: expected,
            actual: "Beta middle. Gamma ending.",
            requiredPhrases: phrases,
            protectedTokens: []
        )
        let missingEnd = TranscriptCompletenessAnalyzer.analyze(
            expected: expected,
            actual: "Alpha opening. Beta middle.",
            requiredPhrases: phrases,
            protectedTokens: []
        )

        #expect(missingBeginning.reasons.contains(.missingRequiredPhrase(phrases[0])))
        #expect(missingEnd.reasons.contains(.missingRequiredPhrase(phrases[2])))
    }

    @Test func catchesMissingProtectedToken() {
        let result = TranscriptCompletenessAnalyzer.analyze(
            expected: "Email Michael about invoice 4837.",
            actual: "Email about the invoice.",
            requiredPhrases: [],
            protectedTokens: ["Michael", "4837"]
        )

        #expect(result.reasons.contains(.missingProtectedToken("Michael")))
        #expect(result.reasons.contains(.missingProtectedToken("4837")))
    }

    @Test func repeatedPhrasesAlignDeterministically() {
        let first = TranscriptAligner.align(
            expected: "now now send now",
            actual: "now send now"
        )
        let second = TranscriptAligner.align(
            expected: "now now send now",
            actual: "now send now"
        )

        #expect(first == second)
        #expect(first.operations.filter { $0.kind == .deletion }.count == 1)
    }
}
