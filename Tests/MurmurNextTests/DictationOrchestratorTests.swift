import Foundation
import Testing
@testable import MurmurNext

@MainActor
struct DictationOrchestratorTests {
    @Test func insertsOnlyTheRepairedFinalTranscript() async throws {
        let audio = TestAudioInput()
        let transcription = TestTranscriptionEngine(text: "Meet Tuesday, sorry, Wednesday at two, actually three.")
        let insertion = TestInsertionService()
        let modelProvider = try TestModelProvider()
        var history: [TranscriptRecord] = []
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: transcription,
            modelProvider: modelProvider,
            insertionService: insertion,
            personalization: { ([], []) },
            historyHandler: { history.append($0) }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(orchestrator.phase == .completed)
        #expect(insertion.insertedTexts == ["Meet Wednesday at three."])
        #expect(history.map(\.text) == ["Meet Wednesday at three."])
        #expect(orchestrator.lastFinalText == "Meet Wednesday at three.")
    }

    @Test func appliesDictionaryAfterRepairAndBeforeInsertion() async throws {
        let audio = TestAudioInput()
        let insertion = TestInsertionService(context: .code)
        let item = DictionaryItem(
            id: UUID(),
            spokenForm: "super base",
            writtenForm: "Supabase",
            context: .code,
            createdAt: Date()
        )
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Use super base."),
            modelProvider: try TestModelProvider(),
            insertionService: insertion,
            personalization: { ([item], []) },
            historyHandler: { _ in }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()
        #expect(insertion.insertedTexts == ["Use Supabase."])
    }

    @Test func anInsertionFailureNeverCreatesHistory() async throws {
        let audio = TestAudioInput()
        let insertion = TestInsertionService(error: TextInsertionError.targetChanged)
        var history: [TranscriptRecord] = []
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Private words."),
            modelProvider: try TestModelProvider(),
            insertionService: insertion,
            personalization: { ([], []) },
            historyHandler: { history.append($0) }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(orchestrator.phase == .failed)
        #expect(history.isEmpty)
        #expect(orchestrator.lastError != nil)
    }

    @Test func cancelStopsCaptureAndCannotInsertLateText() async throws {
        let audio = TestAudioInput()
        let insertion = TestInsertionService()
        let transcription = TestTranscriptionEngine(text: "Should never appear.")
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: transcription,
            modelProvider: try TestModelProvider(),
            insertionService: insertion,
            personalization: { ([], []) },
            historyHandler: { _ in }
        )

        try orchestrator.begin(mode: .pushToTalk)
        await orchestrator.cancel()

        #expect(orchestrator.phase == .cancelled)
        #expect(audio.stopCallCount == 1)
        #expect(insertion.insertedTexts.isEmpty)
    }

    @Test func commandModeTransformsTheSelectionAfterRepairingTheCommand() async throws {
        let audio = TestAudioInput()
        let insertion = TestInsertionService(selectedText: "Hello Quiet World.")
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Um, make this uppercase."),
            modelProvider: try TestModelProvider(),
            insertionService: insertion,
            personalization: { ([], []) },
            historyHandler: { _ in }
        )

        try orchestrator.begin(mode: .command)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(insertion.insertedTexts == ["HELLO QUIET WORLD."])
        #expect(orchestrator.phase == .completed)
    }

    @Test func persistedSettingsControlRepairWhisperRetryAndPreferredModel() async throws {
        let audio = TestAudioInput()
        let transcription = TestTranscriptionEngine(text: "Um, keep this.")
        let insertion = TestInsertionService()
        let modelProvider = try TestModelProvider()
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: transcription,
            modelProvider: modelProvider,
            insertionService: insertion,
            configuration: {
                DictationRuntimeConfiguration(
                    removeSpeechArtifacts: false,
                    whisperAwareCapture: false,
                    cleanupIntensity: .minimal,
                    preferredWhisperModelIdentifier: "small.en"
                )
            },
            personalization: { ([], []) },
            historyHandler: { _ in }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitQuietSpeechFrames()
        await orchestrator.finish()

        #expect(insertion.insertedTexts == ["Um, keep this."])
        #expect(await transcription.lastRequest?.quietSpeechLikely == false)
        #expect(await modelProvider.requestedIdentifiers == ["small.en"])
    }
}

private final class TestAudioInput: AudioInput, @unchecked Sendable {
    private var frameHandler: (@Sendable (AudioFrame) -> Void)?
    private(set) var stopCallCount = 0

    func start(frameHandler: @escaping @Sendable (AudioFrame) -> Void) throws {
        self.frameHandler = frameHandler
    }

    func stop() {
        stopCallCount += 1
        frameHandler = nil
    }

    func emitNormalSpeechFrames() {
        let samples = (0..<3_200).map { index in
            sin(2 * Float.pi * 180 * Float(index) / 16_000) * 0.12
        }
        frameHandler?(AudioFrame(samples: samples, sampleRate: 16_000, capturedAt: .now))
    }

    func emitQuietSpeechFrames() {
        let samples = (0..<3_200).map { index in
            sin(2 * Float.pi * 2_500 * Float(index) / 16_000) * 0.008
        }
        frameHandler?(AudioFrame(samples: samples, sampleRate: 16_000, capturedAt: .now))
    }
}

private actor TestTranscriptionEngine: LocalTranscriptionEngine {
    let text: String
    private(set) var wasCancelled = false
    private(set) var lastRequest: LocalTranscriptionRequest?

    init(text: String) { self.text = text }

    func transcribe(_ request: LocalTranscriptionRequest) async throws -> LocalTranscriptionResult {
        lastRequest = request
        return LocalTranscriptionResult(text: text, usedBeamSize: request.beamSize, elapsed: .milliseconds(12))
    }

    func cancel() {
        wasCancelled = true
    }
}

private actor TestModelProvider: WhisperModelProviding {
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
private final class TestInsertionService: TextInsertionServicing {
    let target: CapturedTextTarget
    let error: Error?
    let selected: String?
    private(set) var insertedTexts: [String] = []

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

    func captureTarget() throws -> CapturedTextTarget { target }

    func insert(_ text: String, into target: CapturedTextTarget) async throws -> TextInsertionOutcome {
        if let error { throw error }
        insertedTexts.append(text)
        return TextInsertionOutcome(method: .accessibility, message: "Inserted")
    }

    func selectedText(in target: CapturedTextTarget) -> String? { selected }

    func pressEnter(in target: CapturedTextTarget) throws {}
}
