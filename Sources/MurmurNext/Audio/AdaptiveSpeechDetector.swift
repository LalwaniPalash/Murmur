import Foundation

struct AudioFrameAnalysis: Equatable, Sendable {
    let rootMeanSquareDecibels: Double
    let peakDecibels: Double
    let relativeEnergyDecibels: Double
    let zeroCrossingRate: Double
    let highFrequencyRatio: Double
    let whisperLikelihood: Double
    let speechProbability: Double
    let isSpeech: Bool
}

struct AdaptiveSpeechDetector: Sendable {
    let sampleRate: Double
    private(set) var noiseFloorDecibels: Double = -72
    private(set) var latestAnalysis: AudioFrameAnalysis?

    private var processedFrameCount = 0
    private var consecutiveSpeechFrames = 0
    private var consecutiveQuietFrames = 0
    private var speechIsActive = false

    private let startFrameCount = 3
    private let endFrameCount = 12
    private let minimumDecibels = -96.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    mutating func process(
        samples: [Float],
        externalVoiceProbability: Double? = nil
    ) -> AudioFrameAnalysis {
        guard samples.isEmpty == false else {
            let analysis = AudioFrameAnalysis(
                rootMeanSquareDecibels: minimumDecibels,
                peakDecibels: minimumDecibels,
                relativeEnergyDecibels: 0,
                zeroCrossingRate: 0,
                highFrequencyRatio: 0,
                whisperLikelihood: 0,
                speechProbability: 0,
                isSpeech: speechIsActive
            )
            latestAnalysis = analysis
            return analysis
        }

        let metrics = Self.metrics(for: samples, minimumDecibels: minimumDecibels)
        let relativeEnergy = metrics.rmsDecibels - noiseFloorDecibels
        let energyProbability = Self.smoothStep(edge0: 5, edge1: 18, value: relativeEnergy)
        let quietSpeechEnergy = Self.smoothStep(edge0: 3.5, edge1: 12, value: relativeEnergy)
        let noiseLikeCue = Self.smoothStep(edge0: 0.10, edge1: 0.34, value: metrics.zeroCrossingRate)
        let highFrequencyCue = Self.smoothStep(edge0: 0.08, edge1: 0.32, value: metrics.highFrequencyRatio)
        let whisperLikelihood = quietSpeechEnergy * ((noiseLikeCue * 0.58) + (highFrequencyCue * 0.42))
        let localProbability = max(energyProbability * 0.82, whisperLikelihood * 0.92)
        let speechProbability = max(localProbability, externalVoiceProbability ?? 0)

        updateSpeechState(probability: speechProbability)
        updateNoiseFloor(rmsDecibels: metrics.rmsDecibels, speechProbability: speechProbability)
        processedFrameCount += 1

        let analysis = AudioFrameAnalysis(
            rootMeanSquareDecibels: metrics.rmsDecibels,
            peakDecibels: metrics.peakDecibels,
            relativeEnergyDecibels: relativeEnergy,
            zeroCrossingRate: metrics.zeroCrossingRate,
            highFrequencyRatio: metrics.highFrequencyRatio,
            whisperLikelihood: whisperLikelihood,
            speechProbability: speechProbability,
            isSpeech: speechIsActive
        )
        latestAnalysis = analysis
        return analysis
    }

    private mutating func updateSpeechState(probability: Double) {
        let startThreshold = 0.52
        let continuationThreshold = 0.22

        if speechIsActive {
            if probability >= continuationThreshold {
                consecutiveQuietFrames = 0
            } else {
                consecutiveQuietFrames += 1
                if consecutiveQuietFrames >= endFrameCount {
                    speechIsActive = false
                    consecutiveSpeechFrames = 0
                }
            }
        } else if probability >= startThreshold {
            consecutiveSpeechFrames += 1
            if consecutiveSpeechFrames >= startFrameCount {
                speechIsActive = true
                consecutiveQuietFrames = 0
            }
        } else {
            consecutiveSpeechFrames = 0
        }
    }

    private mutating func updateNoiseFloor(rmsDecibels: Double, speechProbability: Double) {
        let isInitialCalibration = processedFrameCount < 30
        guard isInitialCalibration || (speechIsActive == false && speechProbability < 0.25) else { return }

        let smoothing = isInitialCalibration ? 0.12 : 0.015
        let boundedMeasurement = min(rmsDecibels, noiseFloorDecibels + 6)
        noiseFloorDecibels = (noiseFloorDecibels * (1 - smoothing)) + (boundedMeasurement * smoothing)
        noiseFloorDecibels = min(max(noiseFloorDecibels, minimumDecibels), -30)
    }

    private static func metrics(for samples: [Float], minimumDecibels: Double) -> (
        rmsDecibels: Double,
        peakDecibels: Double,
        zeroCrossingRate: Double,
        highFrequencyRatio: Double
    ) {
        var squareSum = 0.0
        var peak = 0.0
        var zeroCrossings = 0
        var differenceEnergy = 0.0
        var signalEnergy = 0.0
        var previous = Double(samples[0])

        for (index, sample) in samples.enumerated() {
            let value = Double(sample)
            squareSum += value * value
            signalEnergy += value * value
            peak = max(peak, abs(value))

            if index > 0 {
                if (value >= 0) != (previous >= 0) {
                    zeroCrossings += 1
                }
                let difference = value - previous
                differenceEnergy += difference * difference
            }
            previous = value
        }

        let rms = sqrt(squareSum / Double(samples.count))
        let rmsDecibels = max(20 * log10(max(rms, 0.000_000_1)), minimumDecibels)
        let peakDecibels = max(20 * log10(max(peak, 0.000_000_1)), minimumDecibels)
        let zeroCrossingRate = Double(zeroCrossings) / Double(max(samples.count - 1, 1))
        let highFrequencyRatio = min(differenceEnergy / max(signalEnergy * 4, 0.000_000_001), 1)
        return (rmsDecibels, peakDecibels, zeroCrossingRate, highFrequencyRatio)
    }

    private static func smoothStep(edge0: Double, edge1: Double, value: Double) -> Double {
        guard edge0 < edge1 else { return value >= edge1 ? 1 : 0 }
        let normalized = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return normalized * normalized * (3 - (2 * normalized))
    }
}

struct RollingAudioBuffer: Sendable {
    let capacity: Int
    private(set) var samples: [Float] = []

    init(capacity: Int) {
        self.capacity = max(capacity, 0)
    }

    mutating func append(_ newSamples: [Float]) {
        guard capacity > 0, newSamples.isEmpty == false else { return }
        if newSamples.count >= capacity {
            samples = Array(newSamples.suffix(capacity))
            return
        }

        let overflow = max((samples.count + newSamples.count) - capacity, 0)
        if overflow > 0 {
            samples.removeFirst(overflow)
        }
        samples.append(contentsOf: newSamples)
    }

    mutating func removeAll(keepingCapacity: Bool = true) {
        samples.removeAll(keepingCapacity: keepingCapacity)
    }
}
