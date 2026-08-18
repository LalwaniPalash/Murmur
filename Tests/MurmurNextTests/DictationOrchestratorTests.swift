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

    @Test func anInsertionFailureCreatesRecoverableVersionedHistory() async throws {
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
        #expect(history.count == 1)
        #expect(history[0].text == "Private words.")
        #expect(history[0].insertionSucceeded == false)
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

    @Test func emailModeRoutesTheCompleteDeterministicTranscriptBeforeInsertion() async throws {
        let audio = TestAudioInput()
        let insertion = TestInsertionService(context: .email)
        let router = TestWritingTransformationRouter(result: WritingTransformationRoutingResult(
            status: .applied,
            outputText: "Hello Palash,\n\nPlease review invoice 4821.",
            notice: nil,
            provenance: transformationProvenance(operation: .professionalEmail)
        ))
        var writing = WritingSettings.default
        writing.route = .openAI
        writing.remoteEmailTextAllowed = true
        var savedResult: TranscriptResultVersion?
        var performance: [DictationPerformanceSample] = []
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Hello Palash please review invoice 4821"),
            modelProvider: try TestModelProvider(),
            insertionService: insertion,
            writingRouter: router,
            configuration: { runtimeConfiguration(writing: writing) },
            personalization: { ([], []) },
            historyHandler: { _ in },
            sessionResultHandler: { _, result in savedResult = result },
            performanceHandler: { performance.append($0) }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(insertion.insertedTexts == ["Hello Palash,\n\nPlease review invoice 4821."])
        #expect(await router.requests.map(\.sourceText) == ["Hello Palash please review invoice 4821"])
        #expect(await router.requests.first?.spokenInstruction == nil)
        #expect(savedResult?.writingTransformation?.operation == .professionalEmail)
        #expect(performance.map(\.stage).contains(.transformation))
    }

    @Test func emailProviderFailureStillInsertsTheCompleteDeterministicText() async throws {
        let audio = TestAudioInput()
        let insertion = TestInsertionService(context: .email)
        let source = "Hello Palash this must remain complete."
        let router = TestWritingTransformationRouter(result: WritingTransformationRoutingResult(
            status: .fallback,
            outputText: source,
            notice: "Used complete original",
            provenance: transformationProvenance(
                operation: .professionalEmail,
                validation: .providerFailed,
                failureCode: "provider.timeout"
            )
        ))
        var writing = WritingSettings.default
        writing.route = .openAI
        writing.remoteEmailTextAllowed = true
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: source),
            modelProvider: try TestModelProvider(),
            insertionService: insertion,
            writingRouter: router,
            configuration: { runtimeConfiguration(writing: writing) },
            personalization: { ([], []) },
            historyHandler: { _ in }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(orchestrator.phase == .completed)
        #expect(insertion.insertedTexts == [source])
        #expect(orchestrator.lastTransformationNotice == "Used complete original")
    }

    @Test func unsupportedSemanticCommandUsesTheRouterAndFailureNeverInsertsTheInstruction() async throws {
        let selection = "This selected paragraph must stay unchanged."
        var writing = WritingSettings.default
        writing.route = .localMLX
        let successAudio = TestAudioInput()
        let successInsertion = TestInsertionService(selectedText: selection)
        let successRouter = TestWritingTransformationRouter(result: WritingTransformationRoutingResult(
            status: .applied,
            outputText: "A polished paragraph.",
            notice: nil,
            provenance: transformationProvenance(operation: .semanticCommand)
        ))
        let success = DictationOrchestrator(
            audioInput: successAudio,
            transcriptionEngine: TestTranscriptionEngine(text: "Rewrite this professionally"),
            modelProvider: try TestModelProvider(),
            insertionService: successInsertion,
            writingRouter: successRouter,
            configuration: { runtimeConfiguration(writing: writing) },
            personalization: { ([], []) },
            historyHandler: { _ in }
        )
        try success.begin(mode: .command)
        successAudio.emitNormalSpeechFrames()
        await success.finish()
        #expect(successInsertion.insertedTexts == ["A polished paragraph."])
        #expect(await successRouter.requests.first?.sourceText == selection)
        #expect(await successRouter.requests.first?.spokenInstruction == "Rewrite this professionally")

        let failedAudio = TestAudioInput()
        let failedInsertion = TestInsertionService(selectedText: selection)
        let failedRouter = TestWritingTransformationRouter(result: WritingTransformationRoutingResult(
            status: .fallback,
            outputText: nil,
            notice: "Kept selection",
            provenance: transformationProvenance(
                operation: .semanticCommand,
                validation: .providerFailed,
                failureCode: "local.generation-failed"
            )
        ))
        let failed = DictationOrchestrator(
            audioInput: failedAudio,
            transcriptionEngine: TestTranscriptionEngine(text: "Rewrite this professionally"),
            modelProvider: try TestModelProvider(),
            insertionService: failedInsertion,
            writingRouter: failedRouter,
            configuration: { runtimeConfiguration(writing: writing) },
            personalization: { ([], []) },
            historyHandler: { _ in }
        )
        try failed.begin(mode: .command)
        failedAudio.emitNormalSpeechFrames()
        await failed.finish()

        #expect(failed.phase == .completed)
        #expect(failedInsertion.insertedTexts.isEmpty)
        #expect(failed.lastTransformationNotice == "Kept selection")
    }

    @Test func fnFirstChordCanPromoteActiveCaptureToCommandMode() async throws {
        let audio = TestAudioInput()
        let insertion = TestInsertionService(selectedText: "I think that this is really very useful.")
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "make it more concise"),
            modelProvider: try TestModelProvider(),
            insertionService: insertion,
            personalization: { ([], []) },
            historyHandler: { _ in }
        )

        try orchestrator.begin(mode: .pushToTalk)
        #expect(orchestrator.promoteActiveSessionToCommand())
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(insertion.insertedTexts == ["This is useful."])
        #expect(orchestrator.phase == .completed)
    }

    @Test func commandUpgradeIsRejectedAfterSpeechBegins() async throws {
        let audio = TestAudioInput()
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Ordinary dictation."),
            modelProvider: try TestModelProvider(),
            insertionService: TestInsertionService(),
            personalization: { ([], []) },
            historyHandler: { _ in }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        try await Task.sleep(for: .milliseconds(30))

        #expect(orchestrator.promoteActiveSessionToCommand() == false)
        await orchestrator.cancel()
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
        #expect(await transcription.lastRequest?.beamSize == 1)
        #expect(await transcription.lastRequest?.bestOf == 1)
        #expect(await transcription.lastRequest?.samples.isEmpty == false)
        #expect(await modelProvider.requestedIdentifiers == ["small.en"])
    }

    @Test func capturedSettingsGateBrowserDomainDetectionBeforeTargetClassification() async throws {
        let insertion = TestInsertionService(context: .browser)
        var writing = WritingSettings.default
        writing.browserDomainDetectionAllowed = true
        let orchestrator = DictationOrchestrator(
            audioInput: TestAudioInput(),
            transcriptionEngine: TestTranscriptionEngine(text: "Hello"),
            modelProvider: try TestModelProvider(),
            insertionService: insertion,
            configuration: {
                DictationRuntimeConfiguration(
                    removeSpeechArtifacts: true,
                    whisperAwareCapture: true,
                    cleanupIntensity: .balanced,
                    preferredWhisperModelIdentifier: "small.en",
                    writing: writing
                )
            },
            personalization: { ([], []) },
            historyHandler: { _ in }
        )

        try orchestrator.begin(mode: .pushToTalk)

        #expect(insertion.capturedBrowserDomainDetectionAllowed == true)
        await orchestrator.cancel()
    }

    @Test func recordsContentFreeReleaseLatencyWithoutInventingAnUnusedTransformationStage() async throws {
        let audio = TestAudioInput()
        let insertion = TestInsertionService()
        var samples: [DictationPerformanceSample] = []
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Complete private transcript."),
            modelProvider: try TestModelProvider(),
            insertionService: insertion,
            personalization: { ([], []) },
            historyHandler: { _ in },
            performanceHandler: { samples.append($0) }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(Set(samples.map(\.stage)) == Set(DictationPerformanceStage.allCases).subtracting([.transformation]))
        #expect(samples.allSatisfy { $0.elapsedMilliseconds >= 0 })
        #expect(samples.first(where: { $0.stage == .transcription })?.recordingDurationSeconds ?? 0 > 0)
    }

    @Test func emitsImmutableSessionAndRawAndFinalResult() async throws {
        let audio = TestAudioInput()
        var committed: [(SourceSessionRecord, TranscriptResultVersion)] = []
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Meet Tuesday, sorry, Wednesday."),
            modelProvider: try TestModelProvider(),
            insertionService: TestInsertionService(),
            personalization: { ([], []) },
            historyHandler: { _ in },
            sessionResultHandler: { committed.append(($0, $1)) }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        let pair = try #require(committed.first)
        #expect(committed.count == 1)
        #expect(pair.0.id == pair.1.sessionID)
        #expect(pair.1.rawTranscript == "Meet Tuesday, sorry, Wednesday.")
        #expect(pair.1.finalTranscript == "Meet Wednesday.")
        #expect(pair.1.providerIdentifier == "local-whisper")
        #expect(pair.1.modelIdentifier == "test")
        #expect(pair.1.language == "en")
        #expect(pair.1.insertionSucceeded)
    }

    @Test func persistenceFailureAfterInsertionNeverInsertsTwice() async throws {
        let audio = TestAudioInput()
        let insertion = TestInsertionService()
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Deliver once."),
            modelProvider: try TestModelProvider(),
            insertionService: insertion,
            personalization: { ([], []) },
            historyHandler: { _ in },
            sessionResultHandler: { _, _ in
                throw SecureRecordStoreError.databaseOperation("injected failure")
            }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(insertion.insertedTexts == ["Deliver once."])
        #expect(orchestrator.phase == .completed)
        #expect(orchestrator.lastError?.contains("database") == true)
    }

    @Test func enabledRetentionStreamsProcessedFramesAndSealsOffTheReleasePath() async throws {
        let audio = TestAudioInput()
        let retention = RetentionSessionSpy()
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Retain this."),
            modelProvider: try TestModelProvider(),
            insertionService: TestInsertionService(),
            configuration: {
                DictationRuntimeConfiguration(
                    removeSpeechArtifacts: true,
                    whisperAwareCapture: true,
                    cleanupIntensity: .balanced,
                    preferredWhisperModelIdentifier: "test",
                    audioRetentionPolicy: .sevenDays
                )
            },
            personalization: { ([], []) },
            historyHandler: { _ in },
            retentionSessionFactory: { _, policy, _ in
                #expect(policy == .sevenDays)
                return retention
            }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(retention.sampleCount > 0)
        #expect(retention.wasSealed)
        #expect(retention.wasDiscarded == false)
    }

    @Test func disabledRetentionDoesNotCreateARetentionSession() async throws {
        let audio = TestAudioInput()
        var factoryCalls = 0
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Do not retain."),
            modelProvider: try TestModelProvider(),
            insertionService: TestInsertionService(),
            personalization: { ([], []) },
            historyHandler: { _ in },
            retentionSessionFactory: { _, _, _ in
                factoryCalls += 1
                return RetentionSessionSpy()
            }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(factoryCalls == 0)
    }

    @Test func recoveryJournalTracksSafePhasesAndClearsOnlyAfterPersistence() async throws {
        let audio = TestAudioInput()
        let journal = RecoverySessionSpy()
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: TestTranscriptionEngine(text: "Persist before clearing."),
            modelProvider: try TestModelProvider(),
            insertionService: TestInsertionService(),
            personalization: { ([], []) },
            historyHandler: { _ in },
            recoverySessionFactory: { _, _, _, _, _ in journal }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(journal.phases == [.finalizing, .inserting])
        #expect(journal.wasCompleted)
        #expect(journal.wasCancelled == false)
    }

    @Test func failedTranscriptionLeavesFinalizingJournalForLaunchRecovery() async throws {
        let audio = TestAudioInput()
        let journal = RecoverySessionSpy()
        let transcription = TestTranscriptionEngine(
            script: [.failure(.processFailed(exitCode: 1, message: "injected"))]
        )
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: transcription,
            modelProvider: try TestModelProvider(),
            insertionService: TestInsertionService(),
            personalization: { ([], []) },
            historyHandler: { _ in },
            recoverySessionFactory: { _, _, _, _, _ in journal }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitNormalSpeechFrames()
        await orchestrator.finish()

        #expect(journal.phases == [.finalizing])
        #expect(journal.wasCompleted == false)
        #expect(journal.wasCancelled == false)
    }
}

private func runtimeConfiguration(writing: WritingSettings) -> DictationRuntimeConfiguration {
    DictationRuntimeConfiguration(
        removeSpeechArtifacts: true,
        whisperAwareCapture: true,
        cleanupIntensity: .balanced,
        preferredWhisperModelIdentifier: "small.en",
        writing: writing
    )
}

private func transformationProvenance(
    operation: WritingTransformationOperation,
    validation: TransformationProvenanceValidation = .accepted,
    failureCode: String? = nil
) -> WritingTransformationProvenance {
    WritingTransformationProvenance(
        operation: operation,
        route: .localMLX,
        providerIdentifier: "test",
        modelIdentifier: "test",
        instructionVersion: "test-v1",
        sourceSHA256: String(repeating: "a", count: 64),
        sourceLength: 10,
        outputSHA256: String(repeating: "b", count: 64),
        outputLength: 10,
        duration: 0.1,
        validation: validation,
        failureCode: failureCode
    )
}

private final class RetentionSessionSpy: DictationAudioRetentionSession, @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sealed = false
    private var discarded = false

    var sampleCount: Int { lock.withLock { samples.count } }
    var wasSealed: Bool { lock.withLock { sealed } }
    var wasDiscarded: Bool { lock.withLock { discarded } }

    func enqueue(_ samples: [Float]) {
        lock.withLock { self.samples.append(contentsOf: samples) }
    }

    func seal() { lock.withLock { sealed = true } }
    func discard() { lock.withLock { discarded = true } }
}

private final class RecoverySessionSpy: DictationRecoveryJournalSession, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedPhases: [RecoveryPhase] = []
    private var completed = false
    private var cancelled = false

    var phases: [RecoveryPhase] { lock.withLock { recordedPhases } }
    var wasCompleted: Bool { lock.withLock { completed } }
    var wasCancelled: Bool { lock.withLock { cancelled } }

    func transition(to phase: RecoveryPhase, resultID: UUID?, failureCode: String?) {
        lock.withLock { recordedPhases.append(phase) }
    }

    func complete() { lock.withLock { completed = true } }
    func cancel() { lock.withLock { cancelled = true } }
}

// Shared doubles live in `DictationTestDoubles.swift`.
