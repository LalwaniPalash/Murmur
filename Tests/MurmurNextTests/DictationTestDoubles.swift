import Foundation
@testable import MurmurNext

final class TestAudioInput: AudioInput, @unchecked Sendable {
    private let lock = NSLock()
    private var frameHandler: (@Sendable (AudioFrame) -> Void)?
    private var stopCount = 0

    var stopCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stopCount
    }

    func start(frameHandler: @escaping @Sendable (AudioFrame) -> Void) throws {
        lock.lock()
        self.frameHandler = frameHandler
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stopCount += 1
        frameHandler = nil
        lock.unlock()
    }

    func emitNormalSpeechFrames() {
        emit(Self.speechSamples(count: 3_200))
    }

    func emitQuietSpeechFrames() {
        let samples = (0..<3_200).map { index in
            sin(2 * Float.pi * 2_500 * Float(index) / 16_000) * 0.008
        }
        emit(samples)
    }

    /// One frame is 0.1s at 16 kHz, which is the granularity `SegmentCommitDetector`
    /// thresholds are expressed in.
    func emitSpeech(frames: Int) {
        for _ in 0..<frames { emit(Self.speechSamples(count: 1_600)) }
    }

    func emitSilence(frames: Int) {
        for _ in 0..<frames { emit([Float](repeating: 0, count: 1_600)) }
    }

    /// Delivers arbitrary audio in capture-sized frames, for tests that drive the pipeline
    /// with real recorded or synthesized speech rather than a synthetic tone.
    func emit(audio samples: [Float], framesOf chunkSize: Int = 1_600) {
        var index = 0
        while index < samples.count {
            let end = min(index + chunkSize, samples.count)
            emit(Array(samples[index..<end]))
            index = end
        }
    }

    private func emit(_ samples: [Float]) {
        lock.lock()
        let handler = frameHandler
        lock.unlock()
        handler?(AudioFrame(samples: samples, sampleRate: 16_000, capturedAt: .now))
    }

    private static func speechSamples(count: Int) -> [Float] {
        (0..<count).map { index in
            sin(2 * Float.pi * 180 * Float(index) / 16_000) * 0.12
        }
    }
}

actor TestTranscriptionEngine: LocalTranscriptionEngine {
    enum Response: Sendable {
        case text(String)
        case failure(LocalTranscriptionError)
    }

    private var scripted: [Response]
    private let repeated: Response
    private(set) var requests: [LocalTranscriptionRequest] = []
    private(set) var wasCancelled = false

    var lastRequest: LocalTranscriptionRequest? { requests.last }

    init(text: String) {
        scripted = []
        repeated = .text(text)
    }

    /// Responses are consumed in call order, so a script maps one-to-one onto committed
    /// segments followed by the tail.
    init(script: [Response], then repeated: Response = .text("")) {
        scripted = script
        self.repeated = repeated
    }

    func warmup(model: LocalWhisperModel) {}

    func transcribe(_ request: LocalTranscriptionRequest) async throws -> LocalTranscriptionResult {
        requests.append(request)
        let response = scripted.isEmpty ? repeated : scripted.removeFirst()
        switch response {
        case .text(let text):
            return LocalTranscriptionResult(
                text: text,
                usedBeamSize: request.beamSize,
                elapsed: .milliseconds(12)
            )
        case .failure(let error):
            throw error
        }
    }

    func cancel() {
        wasCancelled = true
    }
}

actor TestModelProvider: WhisperModelProviding {
    let model: LocalWhisperModel
    private(set) var requestedIdentifiers: [String?] = []

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model-\(UUID().uuidString).bin")
        try Data([1]).write(to: url)
        model = LocalWhisperModel(identifier: "test", fileURL: url, byteCount: 1, sha256: "test")
    }

    func selectedModel(preferredIdentifier: String?) async throws -> LocalWhisperModel {
        requestedIdentifiers.append(preferredIdentifier)
        return model
    }
}

@MainActor
final class TestInsertionService: TextInsertionServicing {
    let target: CapturedTextTarget
    let error: Error?
    let selected: String?
    private(set) var insertedTexts: [String] = []
    private(set) var pressedEnter = false
    private(set) var capturedBrowserDomainDetectionAllowed: Bool?

    init(context: WritingContext = .email, error: Error? = nil, selectedText: String? = nil) {
        target = CapturedTextTarget(
            descriptor: TargetApplicationDescriptor(
                processIdentifier: 42,
                bundleIdentifier: "com.example.Editor",
                localizedName: "Editor",
                writingContext: context
            )
        )
        self.error = error
        selected = selectedText
    }

    func captureTarget(browserDomainDetectionAllowed: Bool) throws -> CapturedTextTarget {
        capturedBrowserDomainDetectionAllowed = browserDomainDetectionAllowed
        return target
    }

    func insert(_ text: String, into target: CapturedTextTarget) async throws -> TextInsertionOutcome {
        if let error { throw error }
        insertedTexts.append(text)
        return TextInsertionOutcome(method: .accessibility, message: "Inserted")
    }

    func selectedText(in target: CapturedTextTarget) -> String? { selected }

    func pressEnter(in target: CapturedTextTarget) async throws {
        if let error { throw error }
        pressedEnter = true
    }
}

actor TestWritingTransformationRouter: WritingTransformationRouting {
    let result: WritingTransformationRoutingResult
    private(set) var requests: [WritingTransformationRequest] = []
    private(set) var protectedTerms: [Set<String>] = []

    init(result: WritingTransformationRoutingResult) {
        self.result = result
    }

    func transform(
        _ request: WritingTransformationRequest,
        protectedTerms: Set<String>
    ) async throws -> WritingTransformationRoutingResult {
        requests.append(request)
        self.protectedTerms.append(protectedTerms)
        return result
    }
}

/// Waits for a condition the capture pipeline reaches asynchronously.
///
/// This is a liveness wait, not a latency assertion — it never asserts how long something
/// took, only that it eventually happened.
@MainActor
func waitUntil(
    attempts: Int = 500,
    _ condition: @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}
