import Testing
@testable import MurmurNext

struct DeterministicEmailFormatterTests {
    @Test func separatesGreetingBodyAndSignoffWithoutChangingWords() {
        let source = "Hi Ananya. Please review invoice 4821. The total is 1250 dollars. Please send feedback by August 12 2026. Thanks Palash."

        let formatted = DeterministicEmailFormatter().format(source)

        #expect(formatted == "Hi Ananya.\n\nPlease review invoice 4821. The total is 1250 dollars.\n\nPlease send feedback by August 12 2026.\n\nThanks Palash.")
        #expect(Self.words(formatted) == Self.words(source))
    }

    @Test func preservesExplicitParagraphsAndNeverInventsARecipientOrSignoff() {
        let source = "Please review the proposal.\n\nThe budget is 4200 dollars. Delivery remains September 9 2026."

        let formatted = DeterministicEmailFormatter().format(source)

        #expect(formatted == source)
        #expect(formatted.contains("Hi") == false)
        #expect(formatted.contains("Thanks") == false)
    }

    @Test func structuresTheReportedRespectedGreetingAndPunctuatedSignoff() {
        let source = "Respected sir, I hope this email finds you well. I just wanted to state that I would require an extension for the assignment submission that is due tonight. I request this in lieu of having a high fever, cold and a sore throat. I am planning to visit the hospital today itself in the evening and continue with the medication that is prescribed to me. I thank you for your understanding. Regards."

        let formatted = DeterministicEmailFormatter().format(source)

        #expect(formatted == "Respected sir, I hope this email finds you well.\n\nI just wanted to state that I would require an extension for the assignment submission that is due tonight. I request this in lieu of having a high fever, cold and a sore throat.\n\nI am planning to visit the hospital today itself in the evening and continue with the medication that is prescribed to me. I thank you for your understanding.\n\nRegards.")
        #expect(Self.words(formatted) == Self.words(source))
    }

    private static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: { $0.isWhitespace })
    }
}
