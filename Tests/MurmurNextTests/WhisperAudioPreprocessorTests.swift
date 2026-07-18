import Foundation
import Testing
@testable import MurmurNext

struct WhisperAudioPreprocessorTests {
    @Test func resamplesNativeMicrophoneFramesToSixteenKilohertz() {
        var preprocessor = WhisperAudioPreprocessor(inputSampleRate: 48_000)
        let source = sineWaveSamples(count: 4_800, amplitude: 0.08, frequency: 220, sampleRate: 48_000)
        let result = preprocessor.process(source)

        #expect(abs(result.samples.count - 1_600) <= 1)
        #expect(result.sampleRate == 16_000)
    }

    @Test func raisesQuietSpeechWithoutClipping() {
        var preprocessor = WhisperAudioPreprocessor(inputSampleRate: 16_000)
        var noise = DeterministicNoise(seed: 10)
        for _ in 0..<40 {
            _ = preprocessor.process(noise.make(count: 320, amplitude: 0.0003))
        }

        let quietSpeech = noise.make(count: 3_200, amplitude: 0.007)
        let processed = preprocessor.process(quietSpeech)
        let inputRMS = rootMeanSquare(quietSpeech)
        let outputRMS = rootMeanSquare(processed.samples)

        #expect(outputRMS > inputRMS * 2)
        #expect(processed.samples.map { abs($0) }.max() ?? 0 <= 0.97)
        #expect(processed.appliedGain > 2)
    }

    @Test func boundsGainWhenNormalSpeechFollowsAWhisper() {
        var preprocessor = WhisperAudioPreprocessor(inputSampleRate: 16_000)
        var noise = DeterministicNoise(seed: 11)
        for _ in 0..<40 {
            _ = preprocessor.process(noise.make(count: 320, amplitude: 0.0003))
        }
        for _ in 0..<10 {
            _ = preprocessor.process(noise.make(count: 320, amplitude: 0.006))
        }

        let normal = sineWaveSamples(count: 1_600, amplitude: 0.3, frequency: 190, sampleRate: 16_000)
        let processed = preprocessor.process(normal)
        #expect(processed.samples.map { abs($0) }.max() ?? 0 <= 0.97)
        #expect(processed.appliedGain < 4)
    }

    @Test func rollingBufferKeepsOnlyConfiguredPreroll() {
        var buffer = RollingAudioBuffer(capacity: 5)
        buffer.append([1, 2, 3])
        buffer.append([4, 5, 6, 7])
        #expect(buffer.samples == [3, 4, 5, 6, 7])
    }
}

private struct DeterministicNoise {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func make(count: Int, amplitude: Float) -> [Float] {
        (0..<count).map { _ in
            state = state &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            let unit = Float((state >> 40) & 0xFFFF) / Float(UInt16.max)
            return ((unit * 2) - 1) * amplitude
        }
    }
}

private func sineWaveSamples(count: Int, amplitude: Float, frequency: Float, sampleRate: Float) -> [Float] {
    (0..<count).map { index in
        sin(2 * Float.pi * frequency * Float(index) / sampleRate) * amplitude
    }
}

private func rootMeanSquare(_ samples: [Float]) -> Float {
    guard samples.isEmpty == false else { return 0 }
    return sqrt(samples.reduce(0) { $0 + ($1 * $1) } / Float(samples.count))
}
