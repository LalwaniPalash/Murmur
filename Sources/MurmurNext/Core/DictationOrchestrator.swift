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
    @Published private(set) var lastTransformationNotice: String?
    /// Short label plus one recovery action, for the Flow Bar. The bar cannot read a
    /// sentence; `lastError` keeps the full text for the Hub.
    @Published private(set) var lastErrorLabel: String?
    @Published private(set) var lastErrorRecovery: String?
    @Published private(set) var targetApplication: TargetApplicationDescriptor?

    private let audioInput: AudioInput
    private let transcriptionEngine: any LocalTranscriptionEngine
    private let modelProvider: any WhisperModelProviding
    private let insertionService: any TextInsertionServicing
    private let transformEngine: any LocalTextTransformEngine
    private let writingRouter: (any WritingTransformationRouting)?
    private let writingPolicyResolver = WritingPolicyResolver()
    private let configuration: @MainActor @Sendable () -> DictationRuntimeConfiguration
    private let personalization: @MainActor @Sendable () -> ([DictionaryItem], [SnippetItem])
    private let historyHandler: @MainActor @Sendable (TranscriptRecord) -> Void
    private let sessionResultHandler: @MainActor @Sendable (
        SourceSessionRecord,
        TranscriptResultVersion
    ) async throws -> Void
    private let performanceHandler: @MainActor @Sendable (DictationPerformanceSample) -> Void
    private let retentionSessionFactory: @MainActor @Sendable (
        UUID,
        AudioRetentionPolicy,
        Date
    ) -> (any DictationAudioRetentionSession)?
    private let recoverySessionFactory: @MainActor @Sendable (
        UUID,
        String,
        String?,
        Bool,
        Date
    ) -> (any DictationRecoveryJournalSession)?

    private var machine = DictationSessionStateMachine()
    private var target: CapturedTextTarget?
    private var activeSessionID: UUID?
    private var activeRuntimeConfiguration: DictationRuntimeConfiguration?
    private var activeWritingPolicy: CapturedWritingPolicy?
    private var retentionSession: (any DictationAudioRetentionSession)?
    private var recoverySession: (any DictationRecoveryJournalSession)?

    private var audioProcessor: DictationAudioProcessor?
    private var frameContinuation: AsyncStream<AudioFrame>.Continuation?
    private var captureTask: Task<Void, Never>?
    private var activeSpeechHasBegun = false

    private static let minimumSessionSampleCount = 1_600

    init(
        audioInput: AudioInput,
        transcriptionEngine: any LocalTranscriptionEngine,
        modelProvider: any WhisperModelProviding,
        insertionService: any TextInsertionServicing,
        transformEngine: any LocalTextTransformEngine = HeuristicTextTransformEngine(),
        writingRouter: (any WritingTransformationRouting)? = nil,
        configuration: @escaping @MainActor @Sendable () -> DictationRuntimeConfiguration = { .default },
        personalization: @escaping @MainActor @Sendable () -> ([DictionaryItem], [SnippetItem]),
        historyHandler: @escaping @MainActor @Sendable (TranscriptRecord) -> Void,
        sessionResultHandler: @escaping @MainActor @Sendable (
            SourceSessionRecord,
            TranscriptResultVersion
        ) async throws -> Void = { _, _ in },
        performanceHandler: @escaping @MainActor @Sendable (DictationPerformanceSample) -> Void = { _ in },
        retentionSessionFactory: @escaping @MainActor @Sendable (
            UUID,
            AudioRetentionPolicy,
            Date
        ) -> (any DictationAudioRetentionSession)? = { _, _, _ in nil },
        recoverySessionFactory: @escaping @MainActor @Sendable (
            UUID,
            String,
            String?,
            Bool,
            Date
        ) -> (any DictationRecoveryJournalSession)? = { _, _, _, _, _ in nil }
    ) {
        self.audioInput = audioInput
        self.transcriptionEngine = transcriptionEngine
        self.modelProvider = modelProvider
        self.insertionService = insertionService
        self.transformEngine = transformEngine
        self.writingRouter = writingRouter
        self.configuration = configuration
        self.personalization = personalization
        self.historyHandler = historyHandler
        self.sessionResultHandler = sessionResultHandler
        self.performanceHandler = performanceHandler
        self.retentionSessionFactory = retentionSessionFactory
        self.recoverySessionFactory = recoverySessionFactory
    }

    func begin(mode: DictationMode) throws {
        let runtimeConfiguration = configuration()
        let target = try insertionService.captureTarget(
            browserDomainDetectionAllowed: runtimeConfiguration.writing.browserDomainDetectionAllowed
        )
        let sessionID = try machine.start(
            mode: mode,
            targetBundleIdentifier: target.descriptor.bundleIdentifier
        )
        self.target = target
        targetApplication = target.descriptor
        activeSessionID = sessionID
        activeRuntimeConfiguration = runtimeConfiguration
        activeWritingPolicy = writingPolicyResolver.resolve(
            settings: runtimeConfiguration.writing,
            target: target.descriptor,
            mode: mode,
            installedLocalWritingModelIdentifiers: runtimeConfiguration.installedLocalWritingModelIdentifiers
        )
        let startedAt = machine.session?.startedAt ?? Date()
        recoverySession = recoverySessionFactory(
            sessionID,
            target.descriptor.localizedName,
            target.descriptor.bundleIdentifier,
            runtimeConfiguration.audioRetentionPolicy.isEnabled,
            startedAt
        )
        if runtimeConfiguration.audioRetentionPolicy.isEnabled {
            retentionSession = retentionSessionFactory(
                sessionID,
                runtimeConfiguration.audioRetentionPolicy,
                startedAt
            )
        }
        lastError = nil
        lastErrorLabel = nil
        lastErrorRecovery = nil
        lastTransformationNotice = nil
        lastFinalText = ""
        activeSpeechHasBegun = false
        phase = .calibrating

        // A fresh processor per session: filter, gain, and speech-classifier state must not
        // leak into the next recording.
        let processor = DictationAudioProcessor()
        audioProcessor = processor

        // The capture callback yields into this stream synchronously, and exactly one task
        // drains it. Spawning a `Task` per frame instead would not preserve arrival order,
        // which for audio means silently reassembling the utterance wrong.
        let (frames, continuation) = AsyncStream<AudioFrame>.makeStream(
            bufferingPolicy: .unbounded
        )
        frameContinuation = continuation

        do {
            try audioInput.start { frame in
                continuation.yield(frame)
            }
            captureTask = Task { [weak self] in
                for await frame in frames {
                    await self?.receive(frame, sessionID: sessionID, processor: processor)
                }
            }
            try machine.beginListening(sessionID: sessionID)
            phase = .listening
        } catch {
            continuation.finish()
            frameContinuation = nil
            captureTask?.cancel()
            captureTask = nil
            retentionSession?.discard()
            retentionSession = nil
            recoverySession?.cancel()
            recoverySession = nil
            try? machine.fail(sessionID: sessionID)
            phase = .failed
            lastError = error.localizedDescription
            applyErrorLabels(from: error)
            audioInput.stop()
            throw error
        }
    }

    /// Fn can reach the event tap just before Control even when the user presses the two
    /// keys as one chord. Capture starts immediately as ordinary dictation so no opening
    /// audio is clipped; when Control follows inside the shortcut chord window, only the
    /// session intent changes. The same recording and captured target remain authoritative.
    @discardableResult
    func promoteActiveSessionToCommand() -> Bool {
        guard let sessionID = activeSessionID,
              let target,
              let runtimeConfiguration = activeRuntimeConfiguration,
              activeSpeechHasBegun == false
        else { return false }
        do {
            try machine.promoteToCommand(sessionID: sessionID)
            activeWritingPolicy = writingPolicyResolver.resolve(
                settings: runtimeConfiguration.writing,
                target: target.descriptor,
                mode: .command,
                installedLocalWritingModelIdentifiers: runtimeConfiguration.installedLocalWritingModelIdentifiers
            )
            return true
        } catch {
            return false
        }
    }

    func finish() async {
        guard let sessionID = activeSessionID,
              let target,
              machine.session?.phase == .listening
        else { return }

        let clock = ContinuousClock()
        let releaseStartedAt = clock.now
        var recordingDurationSeconds = 0.0
        defer {
            recordPerformance(
                .totalRelease,
                duration: releaseStartedAt.duration(to: clock.now),
                recordingDurationSeconds: recordingDurationSeconds
            )
        }
        audioInput.stop()
        let drainStartedAt = clock.now
        await drainCapture()
        retentionSession?.seal()
        retentionSession = nil
        if let processor = audioProcessor {
            recordingDurationSeconds = Double(await processor.totalSampleCount) / 16_000
        }
        recordPerformance(
            .captureDrain,
            duration: drainStartedAt.duration(to: clock.now),
            recordingDurationSeconds: recordingDurationSeconds
        )
        // Draining suspends, and the user can hit cancel in that window. Without this the
        // session is already cancelled when `beginFinalizing` runs, and its throw would
        // land in the catch block and report a failure the user never caused.
        guard activeSessionID == sessionID else { return }

        do {
            recoverySession?.transition(to: .finalizing, resultID: nil, failureCode: nil)
            try machine.beginFinalizing(sessionID: sessionID)
            phase = .finalizing
            guard let processor = audioProcessor,
                  await processor.totalSampleCount >= Self.minimumSessionSampleCount
            else {
                throw LocalTranscriptionError.emptyTranscript
            }
            recordingDurationSeconds = Double(await processor.totalSampleCount) / 16_000

            let runtimeConfiguration = activeRuntimeConfiguration ?? configuration()
            let model = try await modelProvider.selectedModel(
                preferredIdentifier: runtimeConfiguration.preferredWhisperModelIdentifier
            )
            let personalization = personalization()
            let vocabularyPrompt = makePrompt(
                dictionary: personalization.0,
                snippets: personalization.1
            )

            // Independently decoded chunks can return plausible, non-empty text while
            // silently omitting words. That gives a stitching pipeline no failure signal.
            // The complete capture is therefore the only authoritative transcription
            // input, including speech before and after any pause.
            let transcriptionStartedAt = clock.now
            let transcript = try await fullBufferTranscript(
                processor: processor,
                model: model,
                vocabularyPrompt: vocabularyPrompt,
                runtimeConfiguration: runtimeConfiguration
            )
            recordPerformance(
                .transcription,
                duration: transcriptionStartedAt.duration(to: clock.now),
                recordingDurationSeconds: recordingDurationSeconds
            )
            guard activeSessionID == sessionID else { return }

            // The repair pass sees the whole utterance exactly once, so self-corrections
            // such as "Meet Tuesday, sorry, Wednesday" can straddle pauses.
            let pipeline = FinalTranscriptPipeline(
                repairEngine: SpeechRepairEngine(),
                personalizer: TranscriptPersonalizer(dictionary: personalization.0, snippets: personalization.1),
                removeSpeechArtifacts: runtimeConfiguration.removeSpeechArtifacts,
                cleanupIntensity: runtimeConfiguration.cleanupIntensity
            )
            let spokenFinal = try pipeline.finalize(
                transcript,
                context: target.descriptor.writingContext
            )
            recordPerformance(
                .repair,
                duration: spokenFinal.timings.repair,
                recordingDurationSeconds: recordingDurationSeconds
            )
            recordPerformance(
                .grounding,
                duration: spokenFinal.timings.grounding,
                recordingDurationSeconds: recordingDurationSeconds
            )
            let finalText: String
            let action: TextTransformAction?
            let writingProvenance: WritingTransformationProvenance?
            let shouldInsert: Bool
            if machine.session?.mode == .command {
                let selectedText = insertionService.selectedText(in: target)
                do {
                    action = try await transformEngine.apply(
                        command: spokenFinal.text,
                        selectedText: selectedText
                    )
                    switch action {
                    case .replace(let text), .insert(let text): finalText = text
                    case .pressEnter: finalText = "Press Enter"
                    case nil: finalText = spokenFinal.text
                    }
                    writingProvenance = nil
                    shouldInsert = true
                } catch TextTransformError.requiresLocalLanguageModel {
                    guard let selectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                          selectedText.isEmpty == false
                    else {
                        throw TextTransformError.selectionRequired
                    }
                    if let routed = try await routeWritingTransformation(
                        sourceText: selectedText,
                        spokenInstruction: spokenFinal.text,
                        operation: .semanticCommand,
                        target: target,
                        personalization: personalization,
                        recordingDurationSeconds: recordingDurationSeconds
                    ) {
                        writingProvenance = routed.provenance
                        if let output = routed.outputText {
                            action = .replace(output)
                            finalText = output
                            shouldInsert = true
                        } else {
                            action = nil
                            finalText = selectedText
                            shouldInsert = false
                        }
                    } else {
                        action = nil
                        finalText = selectedText
                        writingProvenance = nil
                        shouldInsert = false
                        lastTransformationNotice = "Kept selection"
                    }
                }
            } else {
                action = nil
                shouldInsert = true
                let deterministicSource: String
                if shouldFormatEmail(
                    settings: runtimeConfiguration.writing,
                    target: target.descriptor
                ) {
                    deterministicSource = DeterministicEmailFormatter().format(spokenFinal.text)
                } else {
                    deterministicSource = spokenFinal.text
                }
                if let routed = try await routeWritingTransformation(
                    sourceText: deterministicSource,
                    spokenInstruction: nil,
                    operation: .professionalEmail,
                    target: target,
                    personalization: personalization,
                    recordingDurationSeconds: recordingDurationSeconds
                ) {
                    finalText = routed.outputText ?? deterministicSource
                    writingProvenance = routed.provenance
                } else {
                    finalText = deterministicSource
                    writingProvenance = nil
                }
            }
            guard activeSessionID == sessionID else { return }

            try machine.beginInserting(finalText: finalText, sessionID: sessionID)
            phase = .inserting
            recoverySession?.transition(to: .inserting, resultID: nil, failureCode: nil)
            let insertionStartedAt = clock.now
            do {
                if action == .pressEnter {
                    try await insertionService.pressEnter(in: target)
                } else if shouldInsert {
                    _ = try await insertionService.insert(finalText, into: target)
                }
            } catch {
                let records = makeTerminalRecords(
                    sessionID: sessionID,
                    target: target,
                    model: model,
                    rawTranscript: transcript,
                    finalText: finalText,
                    recordingDuration: recordingDurationSeconds,
                    processingDuration: releaseStartedAt.duration(to: clock.now),
                    insertionSucceeded: false,
                    writingTransformation: writingProvenance
                )
                do {
                    try await commitTerminalRecords(session: records.0, result: records.1)
                    recoverySession?.transition(
                        to: .inserting,
                        resultID: records.1.id,
                        failureCode: "insertion-failed"
                    )
                } catch {
                    recoverySession?.transition(
                        to: .inserting,
                        resultID: nil,
                        failureCode: "insertion-and-persistence-failed"
                    )
                }
                throw error
            }
            recordPerformance(
                .insertion,
                duration: insertionStartedAt.duration(to: clock.now),
                recordingDurationSeconds: recordingDurationSeconds
            )
            guard activeSessionID == sessionID else { return }

            let records = makeTerminalRecords(
                sessionID: sessionID,
                target: target,
                model: model,
                rawTranscript: transcript,
                finalText: finalText,
                recordingDuration: recordingDurationSeconds,
                processingDuration: releaseStartedAt.duration(to: clock.now),
                insertionSucceeded: true,
                writingTransformation: writingProvenance
            )
            var persistenceFailure: Error?
            do {
                try await commitTerminalRecords(session: records.0, result: records.1)
            } catch {
                persistenceFailure = error
            }
            try machine.complete(sessionID: sessionID)
            phase = .completed
            lastFinalText = finalText
            if let persistenceFailure {
                recoverySession?.transition(
                    to: .inserting,
                    resultID: nil,
                    failureCode: "persistence-failed"
                )
                recordBackgroundError(persistenceFailure.localizedDescription)
            } else {
                recoverySession?.complete()
            }
            clearActiveSession()
        } catch {
            if machine.session?.phase.isActive == true {
                try? machine.fail(sessionID: sessionID)
            }
            phase = .failed
            lastError = error.localizedDescription
            applyErrorLabels(from: error)
            clearActiveSession(keepingPublishedState: true)
        }
    }

    func cancel() async {
        guard let sessionID = activeSessionID else { return }
        audioInput.stop()
        frameContinuation?.finish()
        frameContinuation = nil
        captureTask?.cancel()
        captureTask = nil
        retentionSession?.discard()
        retentionSession = nil
        recoverySession?.cancel()
        recoverySession = nil
        await transcriptionEngine.cancel()
        try? machine.cancel(sessionID: sessionID)
        phase = .cancelled
        clearActiveSession(keepingPublishedState: true)
    }

    /// Closes the frame stream and waits for every already-yielded frame to be processed,
    /// so nothing spoken just before key release is dropped.
    private func drainCapture() async {
        frameContinuation?.finish()
        frameContinuation = nil
        await captureTask?.value
        captureTask = nil
    }

    private func receive(_ frame: AudioFrame, sessionID: UUID, processor: DictationAudioProcessor) async {
        guard activeSessionID == sessionID else { return }
        let outcome = await processor.ingest(frame)
        guard activeSessionID == sessionID else { return }

        retentionSession?.enqueue(outcome.processedSamples)

        audioLevelDecibels = outcome.levelDecibels
        whisperLikelihood = outcome.whisperLikelihood
        if outcome.speechDetected { activeSpeechHasBegun = true }
    }

    private func shouldFormatEmail(
        settings: WritingSettings,
        target: TargetApplicationDescriptor
    ) -> Bool {
        guard target.writingContext == .email, settings.emailModeEnabled else { return false }
        return settings.disabledApplicationBundleIdentifiers.contains(where: {
            $0.caseInsensitiveCompare(target.bundleIdentifier) == .orderedSame
        }) == false
    }

    private func fullBufferTranscript(
        processor: DictationAudioProcessor,
        model: LocalWhisperModel,
        vocabularyPrompt: String?,
        runtimeConfiguration: DictationRuntimeConfiguration
    ) async throws -> String {
        let isWhispered = await processor.sessionMetrics.isWhispered
        let samples = await processor.allSamples()
        let first = try await transcriptionEngine.transcribe(
            LocalTranscriptionRequest(
                samples: samples,
                model: model,
                language: "en",
                prompt: vocabularyPrompt,
                beamSize: 1,
                bestOf: 1,
                quietSpeechLikely: runtimeConfiguration.whisperAwareCapture && isWhispered
            )
        )
        let regions = await processor.speechRegions
        guard TranscriptCoverageEvaluator.covers(
            speechRegions: regions,
            transcriptionRanges: first.timeRanges
        ) == false else { return first.text }

        let retry = try await transcriptionEngine.transcribe(
            LocalTranscriptionRequest(
                samples: samples,
                model: model,
                language: "en",
                prompt: vocabularyPrompt,
                beamSize: 8,
                bestOf: 8,
                quietSpeechLikely: true,
                forceFullAudioContext: true
            )
        )
        guard TranscriptCoverageEvaluator.covers(
            speechRegions: regions,
            transcriptionRanges: retry.timeRanges
        ) else {
            throw LocalTranscriptionError.incompleteTranscript
        }
        return retry.text
    }

    private func makePrompt(dictionary: [DictionaryItem], snippets: [SnippetItem]) -> String? {
        let terms = dictionary.map(\.writtenForm) + snippets.map(\.trigger)
        guard terms.isEmpty == false else { return nil }
        return "Vocabulary: " + terms.prefix(80).joined(separator: ", ")
    }

    func recordBackgroundError(_ message: String) {
        lastError = message
        lastErrorLabel = "Problem"
        lastErrorRecovery = nil
    }

    private func routeWritingTransformation(
        sourceText: String,
        spokenInstruction: String?,
        operation: WritingTransformationOperation,
        target: CapturedTextTarget,
        personalization: ([DictionaryItem], [SnippetItem]),
        recordingDurationSeconds: Double
    ) async throws -> WritingTransformationRoutingResult? {
        guard let writingRouter,
              let policy = activeWritingPolicy,
              policy.shouldTransform,
              policy.operation == operation
        else {
            return nil
        }

        switch policy.route {
        case .localMLX:
            lastTransformationNotice = "Polishing locally"
        case .openAI:
            lastTransformationNotice = "Polishing with OpenAI"
        case .openAICompatible:
            lastTransformationNotice = "Polishing with provider"
        case .deterministic:
            return nil
        }

        let started = ContinuousClock().now
        let request = WritingTransformationRequest(
            sourceText: sourceText,
            spokenInstruction: spokenInstruction,
            operation: operation,
            applicationCategory: target.descriptor.writingContext.rawValue,
            policy: policy
        )
        let protectedTerms = Set(personalization.0.map(\.writtenForm))
        let routed = try await writingRouter.transform(request, protectedTerms: protectedTerms)
        recordPerformance(
            .transformation,
            duration: started.duration(to: ContinuousClock().now),
            recordingDurationSeconds: recordingDurationSeconds
        )
        lastTransformationNotice = routed.notice
        return routed
    }

    private func recordPerformance(
        _ stage: DictationPerformanceStage,
        duration: Duration,
        recordingDurationSeconds: Double
    ) {
        performanceHandler(DictationPerformanceSample(
            stage: stage,
            recordingDurationSeconds: recordingDurationSeconds,
            elapsedMilliseconds: duration.murmurMilliseconds
        ))
    }

    private func makeTerminalRecords(
        sessionID: UUID,
        target: CapturedTextTarget,
        model: LocalWhisperModel,
        rawTranscript: String,
        finalText: String,
        recordingDuration: TimeInterval,
        processingDuration: Duration,
        insertionSucceeded: Bool,
        writingTransformation: WritingTransformationProvenance?
    ) -> (SourceSessionRecord, TranscriptResultVersion) {
        let startedAt = machine.session?.startedAt ?? Date()
        let endedAt = Date()
        let session = SourceSessionRecord(
            id: sessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            sourceApplication: target.descriptor.localizedName,
            sourceBundleIdentifier: target.descriptor.bundleIdentifier,
            context: target.descriptor.writingContext,
            mode: machine.session?.mode ?? .pushToTalk,
            recordingDuration: recordingDuration
        )
        return (
            session,
            TranscriptResultVersion(
                id: UUID(),
                sessionID: sessionID,
                createdAt: endedAt,
                rawTranscript: rawTranscript,
                finalTranscript: finalText,
                providerIdentifier: "local-whisper",
                modelIdentifier: model.identifier,
                language: "en",
                totalProcessingDuration: processingDuration.murmurMilliseconds / 1_000,
                insertionSucceeded: insertionSucceeded,
                writingTransformation: writingTransformation
            )
        )
    }

    private func commitTerminalRecords(
        session: SourceSessionRecord,
        result: TranscriptResultVersion
    ) async throws {
        try await sessionResultHandler(session, result)
        historyHandler(try SessionResultProjection.history(session: session, results: [result]))
    }

    private func applyErrorLabels(from error: Error) {
        if let insertion = error as? TextInsertionError {
            lastErrorLabel = insertion.flowBarLabel
            lastErrorRecovery = insertion.flowBarRecovery
        } else {
            lastErrorLabel = "Problem"
            lastErrorRecovery = nil
        }
    }

    private func clearActiveSession(keepingPublishedState: Bool = false) {
        activeSessionID = nil
        activeRuntimeConfiguration = nil
        activeWritingPolicy = nil
        recoverySession = nil
        target = nil
        audioProcessor = nil
        frameContinuation?.finish()
        frameContinuation = nil
        captureTask = nil
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
