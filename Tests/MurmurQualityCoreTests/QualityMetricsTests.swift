import Testing

@testable import MurmurQualityCore

struct QualityMetricsTests {
    @Test func computesWordAndCharacterErrorRates() {
        let score = TranscriptScorer.score(
            expected: "send the report",
            actual: "send a report"
        )

        #expect(score.wordSubstitutions == 1)
        #expect(score.wordInsertions == 0)
        #expect(score.wordDeletions == 0)
        #expect(abs(score.wordErrorRate - (1.0 / 3.0)) < 0.000_001)
        #expect(score.characterErrorRate > 0)
    }

    @Test func emptyExpectedTranscriptHasDefinedScores() {
        let bothEmpty = TranscriptScorer.score(expected: "", actual: "")
        let hallucination = TranscriptScorer.score(expected: "", actual: "hello")

        #expect(bothEmpty.wordErrorRate == 0)
        #expect(hallucination.wordErrorRate == 1)
        #expect(hallucination.wordInsertions == 1)
    }

    @Test func groupsCorpusResultsByModelLanguageAndCondition() {
        let results = [
            CorpusFixtureResult.passed(
                fixtureID: "one", model: "small.en", language: "en",
                speechCondition: .normal, score: .perfect
            ),
            CorpusFixtureResult.passed(
                fixtureID: "two", model: "small.en", language: "en",
                speechCondition: .quiet,
                score: TranscriptScore(
                    expectedWordCount: 4, actualWordCount: 4,
                    wordSubstitutions: 1, wordInsertions: 0, wordDeletions: 0,
                    wordErrorRate: 0.25, characterErrorRate: 0.1
                )
            ),
            CorpusFixtureResult.skipped(
                fixtureID: "three", model: "missing", language: "en",
                speechCondition: .normal, reason: "model unavailable"
            ),
        ]

        let report = CorpusQualityReport(results: results)

        #expect(report.groups.count == 2)
        #expect(report.completedFixtureCount == 2)
        #expect(report.skippedFixtureCount == 1)
        #expect(report.groups.first(where: { $0.speechCondition == .quiet })?.meanWordErrorRate == 0.25)
    }
}
