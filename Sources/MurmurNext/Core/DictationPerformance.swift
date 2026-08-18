import Foundation

enum DictationPerformanceStage: String, CaseIterable, Equatable, Sendable {
    case captureDrain
    case transcription
    case repair
    case grounding
    case transformation
    case insertion
    case totalRelease
}

struct DictationPerformanceSample: Equatable, Sendable {
    let stage: DictationPerformanceStage
    let recordingDurationSeconds: Double
    let elapsedMilliseconds: Double
}

extension Duration {
    var murmurMilliseconds: Double {
        let components = self.components
        return (Double(components.seconds) * 1_000)
            + (Double(components.attoseconds) / 1_000_000_000_000_000)
    }
}
