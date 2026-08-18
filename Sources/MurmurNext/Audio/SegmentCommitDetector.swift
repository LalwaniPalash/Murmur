import Foundation

/// How much of a window was speech, and how much of that speech sounded whispered.
struct SpeechMetrics: Equatable, Sendable {
    /// Anything above the floor the detector treats as "still talking". Deliberately more
    /// permissive than `speechSampleCount`: a trailing word said quietly can sit under the
    /// start threshold, and gating the final decoder pass on the strict measure would drop
    /// it from the transcript entirely.
    var voicedSampleCount = 0
    var speechSampleCount = 0
    var whisperedSpeechSampleCount = 0

    var containsSpeech: Bool { speechSampleCount > 0 }

    /// Whispering is a property of a phrase, not of one frame. A single fricative pushes
    /// `whisperLikelihood` to 1.0, and keying off the per-session maximum meant one "sh"
    /// sound sent an ordinary utterance down the sensitive decode path — measured at 863ms
    /// against 150ms for the same audio decoded normally. Requiring most of the speech to
    /// look whispered keeps the expensive pass for people who are actually whispering.
    var isWhispered: Bool { whisperedSpeechSampleCount * 2 > speechSampleCount }

    /// Mirror `AdaptiveSpeechDetector`'s own start and continuation thresholds, so
    /// "speaking" and "still talking" mean the same thing to both.
    static let speakingProbability = 0.52
    static let voicedProbability = 0.22
    static let whisperedLikelihood = 0.42

    mutating func accumulate(_ analysis: AudioFrameAnalysis, sampleCount: Int) {
        guard analysis.speechProbability >= Self.voicedProbability else { return }
        voicedSampleCount += sampleCount

        guard analysis.speechProbability >= Self.speakingProbability else { return }
        speechSampleCount += sampleCount
        if analysis.whisperLikelihood > Self.whisperedLikelihood {
            whisperedSpeechSampleCount += sampleCount
        }
    }
}

/// Decides where a live capture can be cut into an independently transcribable segment.
///
/// Cuts happen only inside a VAD silence gap, never on a timer. Measured: a mid-word cut
/// turned "the cord" into "the course", while cuts taken in a clean pause produced output
/// byte-identical to transcribing the whole utterance in one pass.
///
/// Deliberately reads `speechProbability` rather than `isSpeech`. `AdaptiveSpeechDetector`
/// holds `isSpeech` for a fixed *frame count* after the energy drops, so how long that
/// hangover lasts depends entirely on the buffer size the audio device happens to deliver
/// — about 256ms with the 1024-sample buffers `SystemAudioInput` asks for, but 1.2s if
/// frames arrive four times larger. Measuring the pause in samples instead gives the
/// committer a time constant that does not move with the hardware.
struct SegmentCommitDetector: Sendable {
    enum Decision: Equatable, Sendable {
        case hold
        /// Carries the pending window's metrics, because committing resets them.
        case commit(SpeechMetrics)
    }

    private let minimumSegmentSamples: Int
    private let minimumTrailingSilenceSamples: Int
    private let minimumSpeechSamples: Int

    private(set) var pendingSampleCount = 0
    private(set) var pendingMetrics = SpeechMetrics()
    private var trailingSilenceSampleCount = 0

    /// Half a second is a sentence boundary; a breath or a stop consonant is well under
    /// 0.3s. Cutting inside one of those risks a mid-word split, which measurably changes
    /// the transcript ("the cord" -> "the course").
    init(
        sampleRate: Double = 16_000,
        minimumSegmentSeconds: Double = 1.5,
        minimumTrailingSilenceSeconds: Double = 0.5,
        minimumSpeechSeconds: Double = 0.6
    ) {
        minimumSegmentSamples = Int(minimumSegmentSeconds * sampleRate)
        minimumTrailingSilenceSamples = Int(minimumTrailingSilenceSeconds * sampleRate)
        minimumSpeechSamples = Int(minimumSpeechSeconds * sampleRate)
    }

    /// Feeds one processed frame and reports whether everything pending should now be cut.
    ///
    /// A commit takes the whole pending window including its trailing silence, so the
    /// committed segments and the final tail concatenate back to the untouched capture —
    /// no audio can fall between two cuts.
    mutating func append(analysis: AudioFrameAnalysis, sampleCount: Int) -> Decision {
        guard sampleCount > 0 else { return .hold }
        pendingSampleCount += sampleCount

        pendingMetrics.accumulate(analysis, sampleCount: sampleCount)

        guard analysis.speechProbability < SpeechMetrics.voicedProbability else {
            trailingSilenceSampleCount = 0
            return .hold
        }

        trailingSilenceSampleCount += sampleCount
        guard pendingMetrics.speechSampleCount >= minimumSpeechSamples,
              trailingSilenceSampleCount >= minimumTrailingSilenceSamples,
              pendingSampleCount >= minimumSegmentSamples
        else { return .hold }

        let metrics = pendingMetrics
        reset()
        return .commit(metrics)
    }

    mutating func reset() {
        pendingSampleCount = 0
        pendingMetrics = SpeechMetrics()
        trailingSilenceSampleCount = 0
    }
}
