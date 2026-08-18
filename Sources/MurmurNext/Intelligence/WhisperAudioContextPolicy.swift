import Foundation

enum WhisperAudioContextPolicy {
    static func audioContext(
        forSampleCount sampleCount: Int,
        sampleRate: Double = 16_000
    ) -> Int {
        guard sampleCount > 0, sampleRate > 0 else { return 256 }

        let seconds = Double(sampleCount) / sampleRate
        guard seconds < 30 else { return 0 }

        let scaled = Int(ceil(seconds / 30.0 * 1_500.0)) + 128
        return min(1_500, max(256, scaled))
    }
}
