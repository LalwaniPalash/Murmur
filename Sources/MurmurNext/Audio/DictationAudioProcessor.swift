import Foundation

/// Owns every per-frame audio transform for one dictation session.
///
/// This work used to run on `@MainActor` inside the capture callback — resample,
/// high-pass, VAD, gain, three array allocations per frame — on the same thread that
/// drives the Flow Bar. Here it runs off the main thread, and the orchestrator keeps only
/// published UI state.
///
/// One instance per session: the preprocessor and speech metrics carry filter, gain, and
/// classifier state, none of which may leak across sessions.
actor DictationAudioProcessor {
    struct SpeechRegion: Equatable, Sendable {
        let startSample: Int
        var endSample: Int
    }
    struct FrameOutcome: Sendable {
        let levelDecibels: Double
        let whisperLikelihood: Double
        let processedSamples: [Float]
        let speechDetected: Bool
    }

    private var preprocessor: WhisperAudioPreprocessor?
    private var samples: [Float] = []
    private(set) var speechRegions: [SpeechRegion] = []
    private(set) var sessionMetrics = SpeechMetrics()

    var totalSampleCount: Int { samples.count }

    func ingest(_ frame: AudioFrame) -> FrameOutcome {
        var preprocessor = self.preprocessor ?? WhisperAudioPreprocessor(inputSampleRate: frame.sampleRate)
        let processed = preprocessor.process(frame.samples)
        self.preprocessor = preprocessor

        let frameStart = samples.count
        samples.append(contentsOf: processed.samples)
        // Characterize the complete recording so quiet-speech retry policy is based on the
        // session as a whole rather than one outlier frame.
        sessionMetrics.accumulate(processed.analysis, sampleCount: processed.samples.count)
        if processed.analysis.speechProbability >= SpeechMetrics.voicedProbability {
            let frameEnd = samples.count
            if let last = speechRegions.indices.last, speechRegions[last].endSample == frameStart {
                speechRegions[last].endSample = frameEnd
            } else {
                speechRegions.append(SpeechRegion(startSample: frameStart, endSample: frameEnd))
            }
        }

        return FrameOutcome(
            levelDecibels: processed.analysis.rootMeanSquareDecibels,
            whisperLikelihood: processed.analysis.whisperLikelihood,
            processedSamples: processed.samples,
            speechDetected: processed.analysis.speechProbability >= SpeechMetrics.speakingProbability
        )
    }

    /// The untouched session buffer used by the authoritative final transcription and,
    /// when enabled, retained audio.
    func allSamples() -> [Float] { samples }
}
