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
    private var isCapturing = false

    func start(frameHandler: @escaping @Sendable (AudioFrame) -> Void) throws {
        lock.lock()
        guard engine == nil else {
            lock.unlock()
            throw AudioInputError.alreadyCapturing
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            lock.unlock()
            throw AudioInputError.unavailable
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            // The lock covers the delivery itself, not just the flag read. Callers close
            // their frame stream as soon as `stop()` returns, and a frame handed over after
            // that close is silently discarded — the last word of the utterance. Holding the
            // lock across the handoff means `stop()` can only observe a callback as wholly
            // before it or wholly suppressed. Tap callbacks run on an AVAudioEngine worker
            // rather than the render thread, so a brief uncontended lock is safe here.
            lock.lock()
            defer { lock.unlock() }
            guard isCapturing else { return }
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
            isCapturing = true
            lock.unlock()
        } catch {
            // Released before the tap comes down, for the same reason as `stop()`:
            // `removeTap` waits for an in-flight callback, and that callback is waiting
            // for this lock.
            lock.unlock()
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        lock.lock()
        guard let engine else {
            lock.unlock()
            return
        }
        // Clearing the flag under the lock is what makes the stop point well defined: any
        // callback that has not taken the lock yet will now suppress itself, and any that
        // already ran delivered its frame before this returns.
        isCapturing = false
        self.engine = nil
        // Released before touching the tap. `removeTap` waits for an in-flight callback,
        // and that callback is waiting for this lock — holding it here would deadlock.
        lock.unlock()

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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

    /// Runs on every capture frame, so it allocates one buffer rather than one per stage:
    /// resample and high-pass fill it together, and gain is applied to it in place.
    mutating func process(_ inputSamples: [Float], externalVoiceProbability: Double? = nil) -> ProcessedAudioFrame {
        var samples = resampledHighPass(inputSamples)
        let analysis = detector.process(samples: samples, externalVoiceProbability: externalVoiceProbability)
        let desiredRMS: Double = analysis.whisperLikelihood > 0.35 ? -23 : -19
        let desiredGain = pow(10, (desiredRMS - analysis.rootMeanSquareDecibels) / 20)
        let boundedGain = Float(min(max(desiredGain, 1), 12))
        let isReducing = boundedGain < currentGain
        let smoothing: Float = isReducing ? 0.78 : 0.22
        currentGain += (boundedGain - currentGain) * smoothing

        let gain = currentGain
        for index in samples.indices {
            samples[index] = min(max(samples[index] * gain, -0.97), 0.97)
        }
        return ProcessedAudioFrame(
            samples: samples,
            sampleRate: outputSampleRate,
            analysis: analysis,
            appliedGain: currentGain
        )
    }

    private mutating func resampledHighPass(_ inputSamples: [Float]) -> [Float] {
        guard inputSamples.isEmpty == false else { return [] }

        let cutoff = 70.0
        let timeConstant = 1 / (2 * Double.pi * cutoff)
        let sampleInterval = 1 / outputSampleRate
        let alpha = Float(timeConstant / (timeConstant + sampleInterval))

        let needsResampling = abs(inputSampleRate - outputSampleRate) > 0.5
        let outputCount = needsResampling
            ? max(Int((Double(inputSamples.count) * outputSampleRate / inputSampleRate).rounded()), 1)
            : inputSamples.count
        let scale = inputSampleRate / outputSampleRate

        var output = [Float](repeating: 0, count: outputCount)
        for index in 0..<outputCount {
            let input: Float
            if needsResampling {
                let sourcePosition = Double(index) * scale
                let lower = min(Int(sourcePosition), inputSamples.count - 1)
                let upper = min(lower + 1, inputSamples.count - 1)
                let fraction = Float(sourcePosition - Double(lower))
                input = inputSamples[lower] + ((inputSamples[upper] - inputSamples[lower]) * fraction)
            } else {
                input = inputSamples[index]
            }
            let filtered = alpha * (previousHighPassOutput + input - previousInput)
            previousInput = input
            previousHighPassOutput = filtered
            output[index] = filtered
        }
        return output
    }
}
