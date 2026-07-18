import AVFoundation
import Foundation

struct AudioFrame: Sendable {
    let samples: [Float]
    let sampleRate: Double
    let capturedAt: ContinuousClock.Instant
}

struct ProcessedAudioFrame: Sendable {
    let samples: [Float]
    let sampleRate: Double
    let analysis: AudioFrameAnalysis
    let appliedGain: Float
}

enum AudioInputError: Error, LocalizedError {
    case unavailable
    case invalidFormat
    case alreadyCapturing

    var errorDescription: String? {
        switch self {
        case .unavailable: "No microphone input is available."
        case .invalidFormat: "The selected microphone uses an unsupported audio format."
        case .alreadyCapturing: "Murmur is already listening."
        }
    }
}

protocol AudioInput: AnyObject, Sendable {
    func start(frameHandler: @escaping @Sendable (AudioFrame) -> Void) throws
    func stop()
}

final class SystemAudioInput: AudioInput, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?

    func start(frameHandler: @escaping @Sendable (AudioFrame) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard engine == nil else { throw AudioInputError.alreadyCapturing }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioInputError.unavailable
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            let channelCount = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: frameCount)

            for channel in 0..<channelCount {
                let values = UnsafeBufferPointer(start: channels[channel], count: frameCount)
                for index in 0..<frameCount {
                    mono[index] += values[index] / Float(channelCount)
                }
            }

            frameHandler(
                AudioFrame(
                    samples: mono,
                    sampleRate: format.sampleRate,
                    capturedAt: ContinuousClock.now
                )
            )
        }
        engine.prepare()
        do {
            try engine.start()
            self.engine = engine
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }
}

struct WhisperAudioPreprocessor: Sendable {
    private let inputSampleRate: Double
    private let outputSampleRate = 16_000.0
    private var detector = AdaptiveSpeechDetector(sampleRate: 16_000)
    private var currentGain: Float = 1
    private var previousInput: Float = 0
    private var previousHighPassOutput: Float = 0

    init(inputSampleRate: Double) {
        self.inputSampleRate = inputSampleRate
    }

    mutating func process(_ inputSamples: [Float], externalVoiceProbability: Double? = nil) -> ProcessedAudioFrame {
        let resampled = resample(inputSamples, from: inputSampleRate, to: outputSampleRate)
        let filtered = highPass(resampled)
        let analysis = detector.process(samples: filtered, externalVoiceProbability: externalVoiceProbability)
        let desiredRMS: Double = analysis.whisperLikelihood > 0.35 ? -23 : -19
        let desiredGain = pow(10, (desiredRMS - analysis.rootMeanSquareDecibels) / 20)
        let boundedGain = Float(min(max(desiredGain, 1), 12))
        let isReducing = boundedGain < currentGain
        let smoothing: Float = isReducing ? 0.78 : 0.22
        currentGain += (boundedGain - currentGain) * smoothing

        let processed = filtered.map { sample -> Float in
            let amplified = sample * currentGain
            return min(max(amplified, -0.97), 0.97)
        }
        return ProcessedAudioFrame(
            samples: processed,
            sampleRate: outputSampleRate,
            analysis: analysis,
            appliedGain: currentGain
        )
    }

    private mutating func highPass(_ samples: [Float]) -> [Float] {
        let cutoff = 70.0
        let timeConstant = 1 / (2 * Double.pi * cutoff)
        let sampleInterval = 1 / outputSampleRate
        let alpha = Float(timeConstant / (timeConstant + sampleInterval))
        var output: [Float] = []
        output.reserveCapacity(samples.count)

        for input in samples {
            let filtered = alpha * (previousHighPassOutput + input - previousInput)
            previousInput = input
            previousHighPassOutput = filtered
            output.append(filtered)
        }
        return output
    }

    private func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard samples.isEmpty == false else { return [] }
        guard abs(sourceRate - targetRate) > 0.5 else { return samples }
        let outputCount = max(Int((Double(samples.count) * targetRate / sourceRate).rounded()), 1)
        let scale = sourceRate / targetRate
        return (0..<outputCount).map { outputIndex in
            let sourcePosition = Double(outputIndex) * scale
            let lower = min(Int(sourcePosition), samples.count - 1)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lower))
            return samples[lower] + ((samples[upper] - samples[lower]) * fraction)
        }
    }
}
