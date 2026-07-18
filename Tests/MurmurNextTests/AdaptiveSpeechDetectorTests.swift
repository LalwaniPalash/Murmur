import Foundation
import Testing
@testable import MurmurNext

struct AdaptiveSpeechDetectorTests {
    @Test func calibratesToRoomNoiseWithoutActivating() {
        var detector = AdaptiveSpeechDetector(sampleRate: 16_000)
        var generator = SeededNoiseGenerator(seed: 7)

        for _ in 0..<40 {
            let analysis = detector.process(samples: generator.samples(count: 320, amplitude: 0.00035))
            #expect(analysis.isSpeech == false)
        }

        #expect(detector.noiseFloorDecibels < -60)
        #expect(detector.noiseFloorDecibels > -78)
    }

    @Test func detectsWhisperLikeNoiseAboveTheCalibratedFloor() {
        var detector = calibratedDetector()
        var generator = SeededNoiseGenerator(seed: 91)
        var detectedSpeech = false

        for _ in 0..<12 {
            let analysis = detector.process(samples: generator.samples(count: 320, amplitude: 0.007))
            detectedSpeech = detectedSpeech || analysis.isSpeech
        }

        #expect(detectedSpeech)
        #expect(detector.latestAnalysis?.whisperLikelihood ?? 0 > 0.45)
    }

    @Test func detectsNormallyVoicedSpeech() {
        var detector = calibratedDetector()
        let samples = sineWave(count: 320, amplitude: 0.12, frequency: 180, sampleRate: 16_000)
        var detectedSpeech = false

        for _ in 0..<6 {
            detectedSpeech = detector.process(samples: samples).isSpeech || detectedSpeech
        }

        #expect(detectedSpeech)
        #expect(detector.latestAnalysis?.relativeEnergyDecibels ?? 0 > 20)
    }

    @Test func usesHysteresisToAvoidClippingQuietWordEndings() {
        var detector = calibratedDetector()
        var generator = SeededNoiseGenerator(seed: 12)

        for _ in 0..<8 {
            _ = detector.process(samples: generator.samples(count: 320, amplitude: 0.009))
        }
        #expect(detector.latestAnalysis?.isSpeech == true)

        let firstQuietFrame = detector.process(samples: generator.samples(count: 320, amplitude: 0.0012))
        #expect(firstQuietFrame.isSpeech)

        for _ in 0..<20 {
            _ = detector.process(samples: generator.samples(count: 320, amplitude: 0.00035))
        }
        #expect(detector.latestAnalysis?.isSpeech == false)
    }

    @Test func externalVADCanConfirmAmbiguousLowEnergySpeech() {
        var detector = calibratedDetector()
        var generator = SeededNoiseGenerator(seed: 44)
        var detectedSpeech = false

        for _ in 0..<6 {
            let analysis = detector.process(
                samples: generator.samples(count: 320, amplitude: 0.0011),
                externalVoiceProbability: 0.91
            )
            detectedSpeech = detectedSpeech || analysis.isSpeech
        }

        #expect(detectedSpeech)
    }

    @Test func calibratedRoomNoiseFalseActivationRateStaysBelowOnePercent() {
        var detector = calibratedDetector()
        var generator = SeededNoiseGenerator(seed: 90210)
        var activeFrames = 0
        let frameCount = 1_000

        for index in 0..<frameCount {
            let amplitude: Float = index.isMultiple(of: 17) ? 0.00055 : 0.00035
            if detector.process(samples: generator.samples(count: 320, amplitude: amplitude)).isSpeech {
                activeFrames += 1
            }
        }

        #expect(Double(activeFrames) / Double(frameCount) < 0.01)
    }

    @Test func quietBreathyBurstsRemainDetectableAcrossChangingRoomFloors() {
        var detectedBursts = 0
        let burstCount = 20

        for burst in 0..<burstCount {
            var detector = AdaptiveSpeechDetector(sampleRate: 16_000)
            var generator = SeededNoiseGenerator(seed: UInt64(100 + burst))
            let roomAmplitude = Float(0.00025 + (Double(burst % 4) * 0.00008))
            for _ in 0..<40 {
                _ = detector.process(samples: generator.samples(count: 320, amplitude: roomAmplitude))
            }
            var detected = false
            let whisperAmplitude = roomAmplitude * 14
            for _ in 0..<8 {
                detected = detector.process(
                    samples: generator.samples(count: 320, amplitude: whisperAmplitude)
                ).isSpeech || detected
            }
            if detected { detectedBursts += 1 }
        }

        #expect(Double(detectedBursts) / Double(burstCount) >= 0.95)
    }

    private func calibratedDetector() -> AdaptiveSpeechDetector {
        var detector = AdaptiveSpeechDetector(sampleRate: 16_000)
        var generator = SeededNoiseGenerator(seed: 3)
        for _ in 0..<40 {
            _ = detector.process(samples: generator.samples(count: 320, amplitude: 0.00035))
        }
        return detector
    }
}

private struct SeededNoiseGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func samples(count: Int, amplitude: Float) -> [Float] {
        (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let normalized = Float((state >> 40) & 0xFFFF) / Float(UInt16.max)
            return ((normalized * 2) - 1) * amplitude
        }
    }
}

private func sineWave(count: Int, amplitude: Float, frequency: Float, sampleRate: Float) -> [Float] {
    (0..<count).map { index in
        let phase = 2 * Float.pi * frequency * Float(index) / sampleRate
        return sin(phase) * amplitude
    }
}
