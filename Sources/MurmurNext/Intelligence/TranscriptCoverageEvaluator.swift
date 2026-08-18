import Foundation

enum TranscriptCoverageEvaluator {
    private static let sampleRate = 16_000.0
    private static let minimumRegionSeconds = 0.12
    private static let toleranceSeconds = 0.30

    static func covers(
        speechRegions: [DictationAudioProcessor.SpeechRegion],
        transcriptionRanges: [TranscriptionTimeRange]?
    ) -> Bool {
        // Engines without timestamp support retain the existing text-quality safeguards.
        guard let transcriptionRanges else { return true }
        let meaningfulRegions = speechRegions.filter {
            Double($0.endSample - $0.startSample) / sampleRate >= minimumRegionSeconds
        }
        guard meaningfulRegions.isEmpty == false else { return true }
        guard transcriptionRanges.isEmpty == false else { return false }

        return meaningfulRegions.allSatisfy { region in
            let start = Double(region.startSample) / sampleRate
            let end = Double(region.endSample) / sampleRate
            return transcriptionRanges.contains { transcript in
                transcript.endSeconds + toleranceSeconds >= start &&
                    transcript.startSeconds - toleranceSeconds <= end
            }
        }
    }
}
