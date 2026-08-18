import Testing
@testable import MurmurNext

struct TranscriptCoverageEvaluatorTests {
    @Test func rejectsMissingTailSpeechRegion() {
        let regions = [
            DictationAudioProcessor.SpeechRegion(startSample: 0, endSample: 16_000),
            DictationAudioProcessor.SpeechRegion(startSample: 32_000, endSample: 48_000),
        ]
        #expect(TranscriptCoverageEvaluator.covers(
            speechRegions: regions,
            transcriptionRanges: [.init(startSeconds: 0, endSeconds: 1)]
        ) == false)
    }

    @Test func acceptsRangesCoveringEverySpeechRegion() {
        let regions = [
            DictationAudioProcessor.SpeechRegion(startSample: 0, endSample: 16_000),
            DictationAudioProcessor.SpeechRegion(startSample: 32_000, endSample: 48_000),
        ]
        #expect(TranscriptCoverageEvaluator.covers(
            speechRegions: regions,
            transcriptionRanges: [
                .init(startSeconds: 0, endSeconds: 1),
                .init(startSeconds: 2, endSeconds: 3),
            ]
        ))
    }

    @Test func preservesCompatibilityForEnginesWithoutTimestamps() {
        #expect(TranscriptCoverageEvaluator.covers(
            speechRegions: [.init(startSample: 0, endSample: 16_000)],
            transcriptionRanges: nil
        ))
    }
}
