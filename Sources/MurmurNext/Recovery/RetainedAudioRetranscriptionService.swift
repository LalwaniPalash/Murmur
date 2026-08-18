import Foundation

enum RetainedRetranscriptionError: Error, Equatable, LocalizedError {
    case sessionNotFound
    case parentNotFound
    case plaintextFileRequired

    var errorDescription: String? {
        switch self {
        case .sessionNotFound: "The source recording session is unavailable."
        case .parentNotFound: "The result selected for retranscription is unavailable."
        case .plaintextFileRequired:
            "This local runtime cannot retranscribe retained audio without a plaintext file."
        }
    }
}

actor RetainedAudioRetranscriptionService {
    private let retention: RetentionCoordinator
    private let store: SecureRecordStore
    private let engine: any LocalTranscriptionEngine

    init(
        retention: RetentionCoordinator,
        store: SecureRecordStore,
        engine: any LocalTranscriptionEngine
    ) {
        self.retention = retention
        self.store = store
        self.engine = engine
    }

    func retranscribe(
        sessionID: UUID,
        parentResultID: UUID,
        model: LocalWhisperModel,
        settings: MurmurSettingsRecord,
        dictionary: [DictionaryItem],
        snippets: [SnippetItem]
    ) async throws -> TranscriptResultVersion {
        guard engine.supportsPersistentFileFreeTranscription else {
            throw RetainedRetranscriptionError.plaintextFileRequired
        }
        guard let session = try await store.fetchSourceSessions().first(where: { $0.id == sessionID })
        else { throw RetainedRetranscriptionError.sessionNotFound }
        guard let parent = try await store.fetchResultVersions().first(where: {
            $0.id == parentResultID && $0.sessionID == sessionID
        }) else { throw RetainedRetranscriptionError.parentNotFound }

        let retained = try await retention.samples(sessionID: sessionID)
        let promptTerms = dictionary.map(\.writtenForm) + snippets.map(\.trigger)
        let prompt = promptTerms.isEmpty
            ? nil
            : "Vocabulary: " + promptTerms.prefix(80).joined(separator: ", ")
        let clock = ContinuousClock()
        let startedAt = clock.now
        let raw = try await engine.transcribe(LocalTranscriptionRequest(
            samples: retained.samples,
            model: model,
            language: parent.language,
            prompt: prompt,
            beamSize: 1,
            bestOf: 1
        )).text
        let final = try FinalTranscriptPipeline(
            repairEngine: SpeechRepairEngine(),
            personalizer: TranscriptPersonalizer(dictionary: dictionary, snippets: snippets),
            removeSpeechArtifacts: settings.removeSpeechArtifacts,
            cleanupIntensity: settings.cleanupIntensity
        ).finalize(raw, context: session.context).text
        let result = TranscriptResultVersion(
            id: UUID(),
            sessionID: sessionID,
            parentResultID: parentResultID,
            createdAt: Date(),
            rawTranscript: raw,
            finalTranscript: final,
            providerIdentifier: "local-whisper",
            modelIdentifier: model.identifier,
            language: parent.language,
            totalProcessingDuration: startedAt.duration(to: clock.now).murmurMilliseconds / 1_000,
            insertionSucceeded: false
        )
        try await store.append(result: result)
        try await store.savePreferredResult(PreferredResultRecord(
            sessionID: sessionID,
            resultID: result.id,
            updatedAt: result.createdAt
        ))
        return result
    }

    func recover(
        item: RecoveryItem,
        model: LocalWhisperModel,
        settings: MurmurSettingsRecord,
        dictionary: [DictionaryItem],
        snippets: [SnippetItem]
    ) async throws -> TranscriptResultVersion {
        guard engine.supportsPersistentFileFreeTranscription else {
            throw RetainedRetranscriptionError.plaintextFileRequired
        }
        guard item.retainedAudio != nil else {
            throw EncryptedAudioVaultError.captureNotFound
        }
        let retained = try await retention.samples(sessionID: item.id)
        let promptTerms = dictionary.map(\.writtenForm) + snippets.map(\.trigger)
        let prompt = promptTerms.isEmpty
            ? nil
            : "Vocabulary: " + promptTerms.prefix(80).joined(separator: ", ")
        let clock = ContinuousClock()
        let startedAt = clock.now
        let raw = try await engine.transcribe(LocalTranscriptionRequest(
            samples: retained.samples,
            model: model,
            language: "en",
            prompt: prompt,
            beamSize: 1,
            bestOf: 1
        )).text
        let context = ApplicationContextClassifier().classify(
            bundleIdentifier: item.journal.targetBundleIdentifier ?? "",
            applicationName: item.journal.targetApplication
        )
        let final = try FinalTranscriptPipeline(
            repairEngine: SpeechRepairEngine(),
            personalizer: TranscriptPersonalizer(dictionary: dictionary, snippets: snippets),
            removeSpeechArtifacts: settings.removeSpeechArtifacts,
            cleanupIntensity: settings.cleanupIntensity
        ).finalize(raw, context: context).text
        let duration = Double(retained.samples.count) / Double(max(1, retained.sampleRate))
        let capturedAt = item.retainedAudio?.createdAt ?? item.journal.updatedAt
        let session = SourceSessionRecord(
            id: item.id,
            startedAt: capturedAt,
            endedAt: max(capturedAt, item.journal.updatedAt),
            sourceApplication: item.journal.targetApplication,
            sourceBundleIdentifier: item.journal.targetBundleIdentifier,
            context: context,
            mode: .pushToTalk,
            recordingDuration: duration
        )
        let result = TranscriptResultVersion(
            id: UUID(),
            sessionID: item.id,
            createdAt: Date(),
            rawTranscript: raw,
            finalTranscript: final,
            providerIdentifier: "local-whisper",
            modelIdentifier: model.identifier,
            language: "en",
            totalProcessingDuration: startedAt.duration(to: clock.now).murmurMilliseconds / 1_000,
            insertionSucceeded: false
        )
        try await store.append(session: session, firstResult: result)
        try await store.savePreferredResult(PreferredResultRecord(
            sessionID: session.id,
            resultID: result.id,
            updatedAt: result.createdAt
        ))
        return result
    }
}
