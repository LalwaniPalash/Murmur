import Testing
@testable import MurmurNext

struct SpeechRepairEngineTests {
    @Test(arguments: [
        ("We should, um, test this first.", "We should test this first."),
        ("I, uh, wanted to ask about Friday.", "I wanted to ask about Friday."),
        ("This is is the final version.", "This is the final version."),
        ("Please please send the file.", "Please send the file."),
    ])
    func removesFillersAndImmediateRepetitions(source: String, expected: String) {
        let result = SpeechRepairEngine().repair(source)
        #expect(result.text == expected)
        #expect(result.edits.isEmpty == false)
    }

    @Test(arguments: [
        ("Meet Tuesday, sorry, Wednesday at two, actually three.", "Meet Wednesday at three."),
        ("Email John, I mean Jane, about the launch.", "Email Jane about the launch."),
        ("The total is fifteen, no, sixteen dollars.", "The total is sixteen dollars."),
    ])
    func resolvesExplicitReplacementCorrections(source: String, expected: String) {
        #expect(SpeechRepairEngine().repair(source).text == expected)
    }

    @Test func removesAnAbandonedClauseAfterNoWait() {
        let source = "We should ship this, no wait, test it first."
        #expect(SpeechRepairEngine().repair(source).text == "We should test it first.")
    }

    @Test(arguments: [
        ("Let's meet at two actually three.", "Let's meet at three."),
        ("Send it Friday, or rather, Monday.", "Send it Monday."),
        ("I wanted to I wanted to ask about the launch.", "I wanted to ask about the launch."),
        ("We should ship today. Scratch that. We should test today.", "We should test today."),
        ("The first idea will not work. Start over. The second idea is safer.", "The second idea is safer."),
    ])
    func resolvesNaturalCourseCorrections(source: String, expected: String) {
        #expect(SpeechRepairEngine().repair(source).text == expected)
    }

    @Test func preservesActuallyWhenItIsNotACorrectionMarker() {
        let source = "This is actually useful."
        #expect(SpeechRepairEngine().repair(source).text == source)
    }

    @Test func groundingRejectsAnInventedName() {
        let validator = TranscriptGroundingValidator()
        let result = validator.validate(
            candidate: "Email Priya about the launch.",
            sourceTranscript: "Email Jane about the launch.",
            allowedContext: []
        )

        #expect(result.isGrounded == false)
        #expect(result.unsupportedTokens.contains("Priya"))
    }

    @Test func groundingAcceptsCorrectedEntitiesThatWereSpoken() {
        let validator = TranscriptGroundingValidator()
        let result = validator.validate(
            candidate: "Meet Wednesday at three.",
            sourceTranscript: "Meet Tuesday, sorry, Wednesday at two, actually three.",
            allowedContext: []
        )

        #expect(result.isGrounded)
        #expect(result.unsupportedTokens.isEmpty)
    }

    @Test func groundingAllowsDictionaryTerms() {
        let result = TranscriptGroundingValidator().validate(
            candidate: "Deploy with Supabase.",
            sourceTranscript: "Deploy with super base.",
            allowedContext: ["Supabase"]
        )

        #expect(result.isGrounded)
    }
}
