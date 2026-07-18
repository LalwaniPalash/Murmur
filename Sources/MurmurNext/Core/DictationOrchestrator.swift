import Combine
import Foundation

protocol WhisperModelProviding: Sendable {
    func selectedModel(preferredIdentifier: String?) async throws -> LocalWhisperModel
}

actor InstalledWhisperModelProvider: WhisperModelProviding {
    let catalog: LocalWhisperModelCatalog

    init(catalog: LocalWhisperModelCatalog = LocalWhisperModelCatalog()) {
        self.catalog = catalog
    }

    func selectedModel(preferredIdentifier: String?) async throws -> LocalWhisperModel {
        let models = try await LocalWhisperModelVerificationCache.shared.verifiedModels(in: catalog)
        if let preferredIdentifier,
           let preferred = models.first(where: { $0.identifier == preferredIdentifier }) {
            return preferred
        }
        guard let first = models.first else { throw LocalTranscriptionError.modelUnavailable }
        return first
    }
}

@MainActor
final class DictationOrchestrator: ObservableObject {
    @Published private(set) var phase: DictationPhase = .idle
    @Published private(set) var audioLevelDecibels = -96.0
    @Published private(set) var whisperLikelihood = 0.0
    @Published private(set) var lastFinalText = ""
    @Published private(set) var lastError: String?
    @Published private(set) var targetApplication: TargetApplicationDescriptor?

    private let audioInput: AudioInput
    private let transcriptionEngine: any LocalTranscriptionEngine
    private let modelProvider: any WhisperModelProviding
    private let insertionService: any TextInsertionServicing
    private let transformEngine: any LocalTextTransformEngine
    private let configuration: @MainActor @Sendable () -> DictationRuntimeConfiguration
    private let personalization: @MainActor @Sendable () -> ([DictionaryItem], [SnippetItem])
    private let historyHandler: @MainActor @Sendable (TranscriptRecord) -> Void

    private var machine = DictationSessionStateMachine()
    private var target: CapturedTextTarget?
    private var preprocessor: WhisperAudioPreprocessor?
    private var processedSamples: [Float] = []
    private var activeSessionID: UUID?
    private var peakWhisperLikelihood = 0.0

    init(
        audioInput: AudioInput,
        transcriptionEngine: any LocalTranscriptionEngine,
        modelProvider: any WhisperModelProviding,
        insertionService: any TextInsertionServicing,
        transformEngine: any LocalTextTransformEngine = HeuristicTextTransformEngine(),
        configuration: @escaping @MainActor @Sendable () -> DictationRuntimeConfiguration = { .default },
        personalization: @escaping @MainActor @Sendable () -> ([DictionaryItem], [SnippetItem]),
        historyHandler: @escaping @MainActor @Sendable (TranscriptRecord) -> Void
    ) {
        self.audioInput = audioInput
        self.transcriptionEngine = transcriptionEngine
        self.modelProvider = modelProvider
        self.insertionService = insertionService
        self.transformEngine = transformEngine
        self.configuration = configuration
        self.personalization = personalization
        self.historyHandler = historyHandler
    }

    func begin(mode: DictationMode) throws {
        let target = try insertionService.captureTarget()
        let sessionID = try machine.start(
            mode: mode,
            targetBundleIdentifier: target.descriptor.bundleIdentifier
        )
        self.target = target
        targetApplication = target.descriptor
        activeSessionID = sessionID
        processedSamples.removeAll(keepingCapacity: true)
        preprocessor = nil
        lastError = nil
        lastFinalText = ""
        peakWhisperLikelihood = 0
        phase = .calibrating

        do {
            try audioInput.start { [weak self] frame in
                Task { @MainActor in
                    self?.receive(frame, sessionID: sessionID)
                }
            }
            try machine.beginListening(sessionID: sessionID)
            phase = .listening
        } catch {
            try? machine.fail(sessionID: sessionID)
            phase = .failed
            lastError = error.localizedDescription
            audioInput.stop()
            throw error
        }
    }

    func finish() async {
        guard let sessionID = activeSessionID,
              let target,
              machine.session?.phase == .listening
        else { return }

        audioInput.stop()
        await Task.yield()
        do {
            try machine.beginFinalizing(sessionID: sessionID)
            phase = .finalizing
            guard processedSamples.count >= 1_600 else {
                throw LocalTranscriptionError.emptyTranscript
            }

            let audioURL = try WaveFileEncoder.writeTemporaryFile(samples: processedSamples)
            defer { try? FileManager.default.removeItem(at: audioURL) }
            let runtimeConfiguration = configuration()
            let model = try await modelProvider.selectedModel(
                preferredIdentifier: runtimeConfiguration.preferredWhisperModelIdentifier
            )
            let personalization = personalization()
            let prompt = makePrompt(dictionary: personalization.0, snippets: personalization.1)
            let transcription = try await transcriptionEngine.transcribe(
                LocalTranscriptionRequest(
                    audioFileURL: audioURL,
                    model: model,
                    language: "en",
                    prompt: prompt,
                    beamSize: 5,
                    bestOf: 5,
                    quietSpeechLikely: runtimeConfiguration.whisperAwareCapture && peakWhisperLikelihood > 0.42
                )
            )
            guard activeSessionID == sessionID else { return }

            let pipeline = FinalTranscriptPipeline(
                repairEngine: SpeechRepairEngine(),
                personalizer: TranscriptPersonalizer(dictionary: personalization.0, snippets: personalization.1),
                removeSpeechArtifacts: runtimeConfiguration.removeSpeechArtifacts,
                cleanupIntensity: runtimeConfiguration.cleanupIntensity
            )
            let spokenFinal = try pipeline.finalize(
                transcription.text,
                context: target.descriptor.writingContext
            )
            let finalText: String
            let action: TextTransformAction?
            if machine.session?.mode == .command {
                action = try await transformEngine.apply(
                    command: spokenFinal.text,
                    selectedText: insertionService.selectedText(in: target)
                )
                switch action {
                case .replace(let text), .insert(let text): finalText = text
                case .pressEnter: finalText = "Press Enter"
                case nil: finalText = spokenFinal.text
                }
            } else {
                action = nil
                finalText = spokenFinal.text
            }

            try machine.beginInserting(finalText: finalText, sessionID: sessionID)
            phase = .inserting
            if action == .pressEnter {
                try insertionService.pressEnter(in: target)
            } else {
                _ = try await insertionService.insert(finalText, into: target)
            }
            guard activeSessionID == sessionID else { return }

            try machine.complete(sessionID: sessionID)
            phase = .completed
            lastFinalText = finalText
            let duration = machine.session?.endedAt?.timeIntervalSince(machine.session?.startedAt ?? Date()) ?? 0
            let wordCount = finalText.split(whereSeparator: \.isWhitespace).count
            let wordsPerMinute = duration > 0 ? Double(wordCount) / (duration / 60) : 0
            historyHandler(
                TranscriptRecord(
                    id: sessionID,
                    createdAt: machine.session?.startedAt ?? Date(),
                    sourceApplication: target.descriptor.localizedName,
                    sourceBundleIdentifier: target.descriptor.bundleIdentifier,
                    context: target.descriptor.writingContext,
                    mode: machine.session?.mode ?? .pushToTalk,
                    text: finalText,
                    duration: duration,
                    wordsPerMinute: wordsPerMinute,
                    insertionSucceeded: true
                )
            )
            if runtimeConfiguration.retainRawAudio {
                try? retainAudio(from: audioURL, sessionID: sessionID)
            }
            clearActiveSession()
        } catch {
            if machine.session?.phase.isActive == true {
                try? machine.fail(sessionID: sessionID)
            }
            phase = .failed
            lastError = error.localizedDescription
            clearActiveSession(keepingPublishedState: true)
        }
    }

    func cancel() async {
        guard let sessionID = activeSessionID else { return }
        audioInput.stop()
        await transcriptionEngine.cancel()
        try? machine.cancel(sessionID: sessionID)
        phase = .cancelled
        clearActiveSession(keepingPublishedState: true)
    }

    private func receive(_ frame: AudioFrame, sessionID: UUID) {
        guard activeSessionID == sessionID, phase == .listening else { return }
        if preprocessor == nil {
            preprocessor = WhisperAudioPreprocessor(inputSampleRate: frame.sampleRate)
        }
        guard var preprocessor else { return }
        let processed = preprocessor.process(frame.samples)
        self.preprocessor = preprocessor
        processedSamples.append(contentsOf: processed.samples)
        audioLevelDecibels = processed.analysis.rootMeanSquareDecibels
        whisperLikelihood = processed.analysis.whisperLikelihood
        peakWhisperLikelihood = max(peakWhisperLikelihood, processed.analysis.whisperLikelihood)
    }

    private func makePrompt(dictionary: [DictionaryItem], snippets: [SnippetItem]) -> String? {
        let terms = dictionary.map(\.writtenForm) + snippets.map(\.trigger)
        guard terms.isEmpty == false else { return nil }
        return "Vocabulary: " + terms.prefix(80).joined(separator: ", ")
    }

    private func retainAudio(from temporaryURL: URL, sessionID: UUID) throws {
        try FileManager.default.createDirectory(
            at: MurmurV2Paths.retainedAudioDirectory,
            withIntermediateDirectories: true
        )
        let destination = MurmurV2Paths.retainedAudioDirectory
            .appendingPathComponent("\(sessionID.uuidString).wav")
        let data = try Data(contentsOf: temporaryURL, options: [.mappedIfSafe])
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
    }

    private func clearActiveSession(keepingPublishedState: Bool = false) {
        activeSessionID = nil
        target = nil
        processedSamples.removeAll(keepingCapacity: false)
        preprocessor = nil
        peakWhisperLikelihood = 0
        if keepingPublishedState == false {
            audioLevelDecibels = -96
            whisperLikelihood = 0
        }
    }
}

private extension DictationPhase {
    var isActive: Bool {
        self == .calibrating || self == .listening || self == .finalizing || self == .inserting
    }
}
