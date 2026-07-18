import Foundation
import Testing
@testable import MurmurNext

struct SpeechRepairAcceptanceTests {
    private struct CorpusCase: Decodable {
        let id: String
        let source: String
        let expected: String
    }

    @Test func versionedCorpusMeetsCorrectionAndGroundingReleaseGates() throws {
        let url = try #require(Bundle.module.url(forResource: "repair-corpus-v1", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try JSONDecoder().decode([CorpusCase].self, from: Data(contentsOf: url))
        let engine = SpeechRepairEngine()
        let validator = TranscriptGroundingValidator()
        var correct = 0

        for corpusCase in cases {
            let result = engine.repair(corpusCase.source)
            if result.text == corpusCase.expected {
                correct += 1
            } else {
                Issue.record("\(corpusCase.id): expected ‘\(corpusCase.expected)’, got ‘\(result.text)’")
            }
            let grounding = validator.validate(
                candidate: result.text,
                sourceTranscript: corpusCase.source,
                allowedContext: []
            )
            #expect(grounding.isGrounded, "\(corpusCase.id) introduced protected tokens: \(grounding.unsupportedTokens)")
        }

        #expect(cases.count >= 20)
        #expect(Double(correct) / Double(cases.count) >= 0.95)
    }
}
