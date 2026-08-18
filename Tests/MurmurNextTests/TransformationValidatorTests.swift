import Foundation
import Testing
@testable import MurmurNext

struct TransformationValidatorTests {
    private let validator = TransformationValidator()

    @Test func acceptsProfessionalParagraphingWhenProtectedDetailsRemainExact() {
        let source = "Hi Ananya, please send the proposal to finance@example.com by August 12, 2026. The total is ₹45,000. Thanks, Palash."
        let candidate = "Hi Ananya,\n\nPlease send the proposal to finance@example.com by August 12, 2026. The total is ₹45,000.\n\nThanks,\nPalash"

        let outcome = validator.validate(
            candidate: candidate,
            source: source,
            operation: .professionalEmail
        )

        #expect(outcome.isValid)
        #expect(outcome.failure == nil)
    }

    @Test func rejectsMissingMutatedDuplicatedAndInventedProtectedDetails() {
        let source = "Send it to owner@example.com on 12/08/2026 for $1,250. See https://example.com/plan."

        #expect(validator.validate(
            candidate: "Send it to owner@example.com on 12/08/2026. See https://example.com/plan.",
            source: source,
            operation: .professionalEmail
        ).failure == .protectedDetailMissing("$1,250"))

        #expect(validator.validate(
            candidate: "Send it to other@example.com on 12/08/2026 for $1,250. See https://example.com/plan.",
            source: source,
            operation: .professionalEmail
        ).failure == .protectedDetailInvented("other@example.com"))

        #expect(validator.validate(
            candidate: "Send it to owner@example.com twice: owner@example.com on 12/08/2026 for $1,250. See https://example.com/plan.",
            source: source,
            operation: .professionalEmail
        ).failure == .protectedDetailInvented("owner@example.com"))

        #expect(validator.validate(
            candidate: "Send it to owner@example.com on 13/08/2026 for $1,250. See https://example.com/plan.",
            source: source,
            operation: .professionalEmail
        ).failure == .protectedDetailInvented("13/08/2026"))
    }

    @Test func protectsSourceNamesAndExplicitVocabularyWithoutTreatingNewCapitalizationAsFact() {
        let source = "Palash will send the VSPIR proposal to Ananya tomorrow."
        let valid = "Tomorrow, Palash will send Ananya the VSPIR proposal."
        let missingName = "Tomorrow, Palash will send the VSPIR proposal."

        #expect(validator.validate(
            candidate: valid,
            source: source,
            operation: .professionalEmail,
            protectedTerms: ["VSPIR"]
        ).isValid)
        #expect(validator.validate(
            candidate: missingName,
            source: source,
            operation: .professionalEmail,
            protectedTerms: ["VSPIR"]
        ).failure == .protectedDetailMissing("Ananya"))
    }

    @Test func rejectsEmptyLeakingOversizedAndImplausiblyShortOutput() {
        let source = "Please review the attached proposal and send your comments before Friday afternoon."

        #expect(validator.validate(
            candidate: "  ",
            source: source,
            operation: .professionalEmail
        ).failure == .empty)
        #expect(validator.validate(
            candidate: "Here is the revised email: Please review the proposal.",
            source: source,
            operation: .professionalEmail
        ).failure == .instructionLeakage)
        #expect(validator.validate(
            candidate: String(repeating: "x", count: 40_001),
            source: source,
            operation: .professionalEmail
        ).failure == .oversized)
        #expect(validator.validate(
            candidate: "Review it.",
            source: source,
            operation: .professionalEmail
        ).failure == .implausibleLength)
    }

    @Test func semanticConcisionAllowsMaterialContractionButStillProtectsFacts() {
        let source = "I think that the budget is really very close to $9,500 for launch@example.com."
        let valid = "The budget is close to $9,500 for launch@example.com."

        #expect(validator.validate(
            candidate: valid,
            source: source,
            operation: .semanticCommand
        ).isValid)
        #expect(validator.validate(
            candidate: "The budget is close.",
            source: source,
            operation: .semanticCommand
        ).failure == .protectedDetailMissing("$9,500"))
    }

    @Test(arguments: ["email-golden", "command-golden"])
    func versionedGoldenCorpusMatchesExpectedValidation(fileName: String) throws {
        let url = try #require(Bundle.module.url(
            forResource: fileName,
            withExtension: "json",
            subdirectory: "Fixtures/Transformation"
        ))
        let fixture = try JSONDecoder().decode(TransformationValidationFixture.self, from: Data(contentsOf: url))
        #expect(fixture.schemaVersion == 1)

        for item in fixture.cases {
            let outcome = validator.validate(
                candidate: item.candidate,
                source: item.source,
                operation: item.operation,
                protectedTerms: Set(item.protectedTerms)
            )
            #expect(outcome.isValid == item.expectedValid, "Fixture failed: \(item.id)")
        }
    }
}

private struct TransformationValidationFixture: Decodable {
    let schemaVersion: Int
    let cases: [Case]

    struct Case: Decodable {
        let id: String
        let source: String
        let candidate: String
        let operation: WritingTransformationOperation
        let protectedTerms: [String]
        let expectedValid: Bool
    }
}
