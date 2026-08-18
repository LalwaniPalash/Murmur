import Foundation
import Testing
@testable import MurmurNext

struct SegmentCommitDetectorTests {
    @Test func neverCutsWhileSpeechIsStillActive() {
        var detector = SegmentCommitDetector()
        var decisions: [SegmentCommitDetector.Decision] = []
        // Twelve seconds of unbroken speech: a timer-based committer would have cut here
        // several times, and every cut would have landed mid-word.
        for _ in 0..<120 {
            decisions.append(detector.append(analysis: .speech, sampleCount: 1_600))
        }
        #expect(decisions.allSatisfy { $0 == .hold })
    }

    @Test func cutsOnceSilenceFollowsEnoughSpeech() {
        var detector = SegmentCommitDetector()
        for _ in 0..<20 {
            #expect(detector.append(analysis: .speech, sampleCount: 1_600) == .hold)
        }

        var committed: SegmentCommitDetector.Decision = .hold
        for _ in 0..<10 {
            let decision = detector.append(analysis: .silence, sampleCount: 1_600)
            if case .commit = decision {
                committed = decision
                break
            }
        }
        #expect(
            committed == .commit(
                SpeechMetrics(
                    voicedSampleCount: 32_000,
                    speechSampleCount: 32_000,
                    whisperedSpeechSampleCount: 0
                )
            )
        )
    }

    @Test func holdsWhenTheTrailingSilenceIsTooBriefToBeAPause() {
        var detector = SegmentCommitDetector()
        for _ in 0..<20 {
            _ = detector.append(analysis: .speech, sampleCount: 1_600)
        }
        // 0.1s of silence — a stop consonant, not a pause.
        #expect(detector.append(analysis: .silence, sampleCount: 1_600) == .hold)
    }

    @Test func holdsWhenTheWindowHoldsTooLittleSpeechToBeWorthAPass() {
        var detector = SegmentCommitDetector()
        // 0.2s of speech inside a long quiet window: a cough, not a phrase.
        _ = detector.append(analysis: .speech, sampleCount: 3_200)
        var decisions: [SegmentCommitDetector.Decision] = []
        for _ in 0..<20 {
            decisions.append(detector.append(analysis: .silence, sampleCount: 1_600))
        }
        #expect(decisions.allSatisfy { $0 == .hold })
    }

    @Test func startsFreshAfterEachCut() {
        var detector = SegmentCommitDetector()
        for _ in 0..<20 { _ = detector.append(analysis: .speech, sampleCount: 1_600) }
        for _ in 0..<10 { _ = detector.append(analysis: .silence, sampleCount: 1_600) }

        // Continued silence must not re-fire: the pending window is empty again.
        var decisions: [SegmentCommitDetector.Decision] = []
        for _ in 0..<20 {
            decisions.append(detector.append(analysis: .silence, sampleCount: 1_600))
        }
        #expect(decisions.allSatisfy { $0 == .hold })
        #expect(detector.pendingMetrics == SpeechMetrics())
    }
}

private extension AudioFrameAnalysis {
    static let speech = AudioFrameAnalysis(
        rootMeanSquareDecibels: -22,
        peakDecibels: -12,
        relativeEnergyDecibels: 30,
        zeroCrossingRate: 0.12,
        highFrequencyRatio: 0.1,
        whisperLikelihood: 0,
        speechProbability: 0.9,
        isSpeech: true
    )

    static let silence = AudioFrameAnalysis(
        rootMeanSquareDecibels: -70,
        peakDecibels: -62,
        relativeEnergyDecibels: 1,
        zeroCrossingRate: 0.02,
        highFrequencyRatio: 0.01,
        whisperLikelihood: 0,
        speechProbability: 0.02,
        isSpeech: false
    )
}
