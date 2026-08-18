import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppEnvironment: ObservableObject {
    private static let logger = Logger(subsystem: "Murmur", category: "Transcription")

    @Published var selectedDestination: HubDestination = .record
    /// Set when a note is chosen outside the Scratchpad window, so opening the window
    /// lands on that note instead of falling back to the most recent one.
    @Published var requestedScratchpadNote: UUID?
    @Published private(set) var history: [TranscriptRecord] = []
    @Published private(set) var dictionary: [DictionaryItem] = []
    @Published private(set) var snippets: [SnippetItem] = []
    @Published private(set) var styles: [WritingStyle] = AppEnvironment.defaultStyles
    @Published private(set) var notes: [ScratchpadNote] = []
    @Published private(set) var noteRevisions: [ScratchpadRevision] = []
    @Published var searchText = ""
    @Published private(set) var isLoaded = false
    @Published private(set) var persistenceError: String?
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var settings: MurmurSettingsRecord = .default
    @Published private(set) var verifiedWhisperModelIdentifiers: Set<String> = []
    @Published private(set) var recoveryItems: [RecoveryItem] = []
    @Published private(set) var retainedAudioSessionIDs: Set<UUID> = []
    @Published private(set) var isCaptureOwner = false
    @Published private(set) var providerCredentialIdentifiers: Set<String> = []
    @Published private(set) var isLocalWritingModelInstalled = false
    @Published private(set) var installedLocalWritingModelIdentifiers: Set<String> = []
    @Published private(set) var isWritingSetupBusy = false
    @Published private(set) var writingSetupMessage: String?

    let permissionCenter = PermissionCenter()
    let modelInstaller = WhisperModelInstaller()
    let localWritingModelTransfer = LocalWritingModelTransfer()
    private let transcriptionEngine: any LocalTranscriptionEngine
    private let modelProvider: any WhisperModelProviding
    private var store: SecureRecordStore?
    private var retentionCoordinator: RetentionCoordinator?
    private var recoveryCoordinator: RecoveryCoordinator?
    private var sourceSessions: [SourceSessionRecord] = []
    private var resultVersions: [TranscriptResultVersion] = []
    private var preferredResults: [PreferredResultRecord] = []
    private var retainedAudioPlayback: RetainedAudioPlayback?
    private var issueBundleService: IssueBundleService?
    private let shortcutMonitor = GlobalShortcutMonitor()
    private let instanceLock = AppInstanceLock(
        url: MurmurV2Paths.rootDirectory.appendingPathComponent("capture-owner.lock")
    )
    private var shortcutsStarted = false
    private var subscriptions: Set<AnyCancellable> = []
    private var transcriptionWarmupTask: Task<Void, Never>?

    private lazy var writingRouter = WritingTransformationRouter(
        openAIEngine: OpenAITextTransformationEngine(),
        compatibleEngine: OpenAITextTransformationEngine(
            baseURL: nil,
            acceptedRoute: .openAICompatible
        ),
        localEngine: LocalMLXTextTransformationEngine()
    )

    lazy var dictationOrchestrator = DictationOrchestrator(
        audioInput: SystemAudioInput(),
        transcriptionEngine: transcriptionEngine,
        modelProvider: modelProvider,
        insertionService: TextInsertionCoordinator(),
        writingRouter: writingRouter,
        configuration: { [weak self] in
            DictationRuntimeConfiguration(
                settings: self?.settings ?? .default,
                installedLocalWritingModelIdentifiers: self?.installedLocalWritingModelIdentifiers ?? []
            )
        },
        personalization: { [weak self] in
            (self?.dictionary ?? [], self?.snippets ?? [])
        },
        historyHandler: { _ in },
        sessionResultHandler: { [weak self] session, result in
            guard let self else { return }
            try await self.commit(session: session, firstResult: result)
        },
        retentionSessionFactory: { [weak self] sessionID, policy, createdAt in
            guard policy.isEnabled, let coordinator = self?.retentionCoordinator else { return nil }
            return BackgroundAudioRetentionSession(
                coordinator: coordinator,
                sessionID: sessionID,
                policy: policy,
                sampleRate: 16_000,
                createdAt: createdAt,
                errorHandler: { [weak self] message in
                    Task { @MainActor in self?.persistenceError = message }
                },
                completionHandler: { [weak self] sessionID in
                    Task { @MainActor in self?.retainedAudioSessionIDs.insert(sessionID) }
                }
            )
        },
        recoverySessionFactory: { [weak self] sessionID, app, bundleID, hasAudio, startedAt in
            guard let coordinator = self?.recoveryCoordinator else { return nil }
            return BackgroundRecoveryJournalSession(
                coordinator: coordinator,
                sessionID: sessionID,
                targetApplication: app,
                targetBundleIdentifier: bundleID,
                retainedAudioAvailable: hasAudio,
                startedAt: startedAt,
                errorHandler: { [weak self] message in
                    Task { @MainActor in self?.persistenceError = message }
                }
            )
        }
    )

    lazy var flowBarController = FlowBarController(orchestrator: dictationOrchestrator)

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "Murmur.v2.onboardingCompleted")
        transcriptionEngine = Self.makeTranscriptionEngine()
        modelProvider = InstalledWhisperModelProvider()
        configureShortcuts()
        modelInstaller.$state
            .sink { [weak self] state in
                guard case .installed(let manifest) = state else { return }
                Task { @MainActor in
                    guard let self else { return }
                    await self.refreshVerifiedWhisperModels()
                    self.activateWhisperModel(identifier: manifest.id)
                    self.scheduleTranscriptionWarmup()
                }
            }
            .store(in: &subscriptions)
        localWritingModelTransfer.$state
            .sink { [weak self] state in
                guard state == .installed else { return }
                Task { @MainActor in await self?.refreshWritingSetupState() }
            }
            .store(in: &subscriptions)
    }

    var usage: UsageSummary {
        guard history.isEmpty == false else { return .empty }
        let words = history.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        let usedDays = Set(history.map { Calendar.current.startOfDay(for: $0.createdAt) }).count
        let averageWPM = history.map(\.wordsPerMinute).reduce(0, +) / Double(history.count)
        return UsageSummary(words: words, sessions: history.count, averageWordsPerMinute: averageWPM, daysUsed: usedDays)
    }

    func start() async {
        guard isLoaded == false, store == nil else { return }
        do {
            try MurmurV2Paths.prepareDirectories()
            isCaptureOwner = try instanceLock.acquire()
            let key = try await KeychainMasterKeyStore.shared.loadOrCreateKey()
            let store = try SecureRecordStore(url: MurmurV2Paths.databaseURL, key: key)
            self.store = store
            let retentionCoordinator = RetentionCoordinator(
                vault: EncryptedAudioVault(
                    rootURL: MurmurV2Paths.retainedAudioDirectory,
                    masterKey: key
                ),
                store: store
            )
            self.retentionCoordinator = retentionCoordinator
            retainedAudioPlayback = RetainedAudioPlayback(retention: retentionCoordinator)
            issueBundleService = IssueBundleService(retention: retentionCoordinator)
            let recoveryCoordinator = RecoveryCoordinator(
                store: store,
                retention: retentionCoordinator
            )
            self.recoveryCoordinator = recoveryCoordinator
            try await store.migrateHistoryToVersionedRecordsIfNeeded()

            async let storedHistory = store.fetchVersionedHistory()
            async let storedSessions = store.fetchSourceSessions()
            async let storedResults = store.fetchResultVersions()
            async let storedDictionary: [DictionaryItem] = store.fetch(collection: .dictionary)
            async let storedSnippets: [SnippetItem] = store.fetch(collection: .snippets)
            async let storedStyles: [WritingStyle] = store.fetch(collection: .styles)
            async let storedNotes: [ScratchpadNote] = store.fetch(collection: .notes)
            async let storedRevisions: [ScratchpadRevision] = store.fetch(collection: .noteRevisions)
            async let storedSettings: [MurmurSettingsRecord] = store.fetch(collection: .settings, limit: 1)
            let loaded = try await (
                storedHistory,
                storedSessions,
                storedResults,
                storedDictionary,
                storedSnippets,
                storedStyles,
                storedNotes,
                storedRevisions,
                storedSettings
            )
            history = loaded.0
            sourceSessions = loaded.1
            resultVersions = loaded.2
            preferredResults = try await store.fetchPreferredResults()
            retainedAudioSessionIDs = Set(try await store.fetchRetainedAudio().map(\.id))
            dictionary = loaded.3
            snippets = loaded.4
            styles = Self.mergeStyles(stored: loaded.5)
            let storedStyleIDs = Set(loaded.5.map(\.id))
            for style in styles where storedStyleIDs.contains(style.id) == false {
                try await store.save(
                    style,
                    collection: .styles,
                    searchableText: "\(style.name) \(style.instructions)"
                )
            }
            notes = loaded.6
            noteRevisions = loaded.7
            settings = loaded.8.first ?? .default
            await refreshWritingSetupState()
            _ = try await retentionCoordinator.migrateLegacyRecordings(
                policy: settings.audioRetentionPolicy
            )
            try await retentionCoordinator.reconcileOrphanedCiphertext()
            _ = try await retentionCoordinator.purgeExpired(at: Date())
            retainedAudioSessionIDs = Set(try await store.fetchRetainedAudio().map(\.id))
            recoveryItems = try await recoveryCoordinator.reconcile()
            isLoaded = true
            permissionCenter.refresh()
            _ = flowBarController
            flowBarController.apply(settings: settings)
            startShortcutsIfPossible()
            scheduleTranscriptionWarmup()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "Murmur.v2.onboardingCompleted")
        permissionCenter.refresh()
        startShortcutsIfPossible()
    }

    func clearPresentedError() {
        persistenceError = nil
    }

    func hasProviderCredential(_ providerIdentifier: String) -> Bool {
        providerCredentialIdentifiers.contains(providerIdentifier)
    }

    func saveProviderCredential(_ credential: String, providerIdentifier: String) async {
        isWritingSetupBusy = true
        writingSetupMessage = nil
        defer { isWritingSetupBusy = false }
        do {
            try await ProviderCredentialStore.shared.save(
                credential,
                providerIdentifier: providerIdentifier
            )
            providerCredentialIdentifiers.insert(providerIdentifier)
            writingSetupMessage = "Key saved in Keychain"
        } catch {
            writingSetupMessage = error.localizedDescription
        }
    }

    func deleteProviderCredential(providerIdentifier: String) async {
        isWritingSetupBusy = true
        writingSetupMessage = nil
        defer { isWritingSetupBusy = false }
        do {
            try await ProviderCredentialStore.shared.delete(providerIdentifier: providerIdentifier)
            providerCredentialIdentifiers.remove(providerIdentifier)
            writingSetupMessage = "Key removed"
        } catch {
            writingSetupMessage = error.localizedDescription
        }
    }

    func testSelectedWritingProvider() async {
        let writing = settings.writing
        guard writing.route == .openAI || writing.route == .openAICompatible else {
            writingSetupMessage = "Select a BYOK provider first"
            return
        }
        isWritingSetupBusy = true
        writingSetupMessage = nil
        defer { isWritingSetupBusy = false }

        var testSettings = writing
        testSettings.remoteEmailTextAllowed = true
        let descriptor = TargetApplicationDescriptor(
            processIdentifier: 0,
            bundleIdentifier: "app.murmur.setup-check",
            localizedName: "Murmur setup check",
            writingContext: .email
        )
        let policy = WritingPolicyResolver().resolve(
            settings: testSettings,
            target: descriptor,
            mode: .pushToTalk
        )
        guard policy.shouldTransform else {
            writingSetupMessage = "Complete the provider URL and model first"
            return
        }
        let request = WritingTransformationRequest(
            sourceText: "Murmur provider setup check.",
            spokenInstruction: nil,
            operation: .professionalEmail,
            applicationCategory: "Setup check",
            policy: policy
        )
        do {
            let engine: any WritingTextTransformationEngine = writing.route == .openAI
                ? OpenAITextTransformationEngine()
                : OpenAITextTransformationEngine(baseURL: nil, acceptedRoute: .openAICompatible)
            _ = try await engine.transform(request)
            writingSetupMessage = "Connection verified"
        } catch {
            writingSetupMessage = error.localizedDescription
        }
    }

    func installLocalWritingModel(_ manifest: LocalWritingModelManifest = .qwen3_0_6B_4Bit) async {
        localWritingModelTransfer.install(manifest)
        writingSetupMessage = nil
    }

    func removeLocalWritingModel(_ manifest: LocalWritingModelManifest? = nil) async {
        guard isWritingSetupBusy == false else { return }
        isWritingSetupBusy = true
        writingSetupMessage = nil
        defer { isWritingSetupBusy = false }
        do {
            if let manifest { localWritingModelTransfer.select(manifest) }
            try localWritingModelTransfer.remove()
            await refreshWritingSetupState()
            writingSetupMessage = "Local writing model removed"
        } catch {
            writingSetupMessage = error.localizedDescription
        }
    }

    func refreshWritingSetupState() async {
        var credentials: Set<String> = []
        for identifier in ["openai", "openai-compatible"] {
            if (try? await ProviderCredentialStore.shared.contains(providerIdentifier: identifier)) == true {
                credentials.insert(identifier)
            }
        }
        providerCredentialIdentifiers = credentials
        let installed = await Task.detached(priority: .utility) {
            let catalog = LocalWritingModelCatalog()
            return Set(LocalWritingModelManifest.supported.compactMap { manifest in
                (try? catalog.verifiedModelDirectory(identifier: manifest.id)) == nil ? nil : manifest.id
            })
        }.value
        installedLocalWritingModelIdentifiers = installed
        isLocalWritingModelInstalled = installed.contains(settings.writing.localModelIdentifier)
    }

    var hasInstalledWhisperModel: Bool {
        verifiedWhisperModelIdentifiers.isEmpty == false
    }

    func refreshVerifiedWhisperModels() async {
        do {
            let verifiedModels = try await LocalWhisperModelVerificationCache.shared.verifiedModels(
                in: LocalWhisperModelCatalog()
            )
            verifiedWhisperModelIdentifiers = Set(verifiedModels.map(\.identifier))
        } catch {
            verifiedWhisperModelIdentifiers = []
            persistenceError = error.localizedDescription
        }
    }

    func activateWhisperModel(identifier: String) {
        guard verifiedWhisperModelIdentifiers.contains(identifier) else { return }
        updateSettings { $0.preferredWhisperModelIdentifier = identifier }
        scheduleTranscriptionWarmup()
    }

    func removeWhisperModel(_ manifest: WhisperDownloadManifest) async throws {
        if case .downloading(let active) = modelInstaller.state, active.id == manifest.id {
            throw WhisperModelManagementError.downloadInProgress
        }
        if case .verifying(let active) = modelInstaller.state, active.id == manifest.id {
            throw WhisperModelManagementError.downloadInProgress
        }

        let installedBeforeRemoval = verifiedWhisperModelIdentifiers
        try LocalWhisperModelCatalog().removeModel(identifier: manifest.id)
        await LocalWhisperModelVerificationCache.shared.invalidate()
        await refreshVerifiedWhisperModels()

        guard settings.preferredWhisperModelIdentifier == manifest.id else { return }
        let fallback = WhisperModelSelectionPolicy.fallback(
            afterRemoving: manifest.id,
            installedIdentifiers: installedBeforeRemoval
        ) ?? WhisperModelSelectionPolicy.recommendedIdentifier
        updateSettings { $0.preferredWhisperModelIdentifier = fallback }
    }

    func beginDictation(mode: DictationMode = .pushToTalk) {
        guard isCaptureOwner else {
            persistenceError = "Another Murmur window owns microphone shortcuts. Use that window to dictate."
            return
        }
        do {
            try dictationOrchestrator.begin(mode: mode)
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func configureShortcuts() {
        shortcutMonitor.onDictationPressed = { [weak self] in
            self?.beginDictation()
        }
        shortcutMonitor.onDictationReleased = { [weak self] in
            Task { await self?.dictationOrchestrator.finish() }
        }
        shortcutMonitor.onCommandPressed = { [weak self] in
            guard self?.settings.commandModeEnabled == true else { return }
            self?.beginDictation(mode: .command)
        }
        shortcutMonitor.onCommandUpgrade = { [weak self] in
            guard self?.settings.commandModeEnabled == true else { return false }
            return self?.dictationOrchestrator.promoteActiveSessionToCommand() == true
        }
        shortcutMonitor.onCommandReleased = { [weak self] in
            Task { await self?.dictationOrchestrator.finish() }
        }
        shortcutMonitor.onCancel = { [weak self] in
            Task { await self?.dictationOrchestrator.cancel() }
        }
    }

    private func startShortcutsIfPossible() {
        guard isCaptureOwner,
              shortcutsStarted == false,
              permissionCenter.accessibilityGranted
        else { return }
        shortcutsStarted = shortcutMonitor.start()
    }

    @discardableResult
    func addDictionaryItem(spokenForm: String, writtenForm: String, context: WritingContext?) -> Bool {
        do {
            try PersonalizationInputValidator().validateDictionary(
                spokenForm: spokenForm,
                writtenForm: writtenForm,
                context: context,
                existing: dictionary
            )
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
        let item = DictionaryItem(
                id: UUID(),
                spokenForm: spokenForm.trimmingCharacters(in: .whitespacesAndNewlines),
                writtenForm: writtenForm.trimmingCharacters(in: .whitespacesAndNewlines),
                context: context,
                createdAt: Date()
        )
        dictionary.append(item)
        persist(item, collection: .dictionary, searchableText: "\(item.spokenForm) \(item.writtenForm)")
        return true
    }

    @discardableResult
    func addSnippet(trigger: String, expansion: String) -> Bool {
        do {
            try PersonalizationInputValidator().validateSnippet(
                trigger: trigger,
                expansion: expansion,
                existing: snippets
            )
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
        let item = SnippetItem(
                id: UUID(),
                trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
                expansion: expansion,
                createdAt: Date()
        )
        snippets.append(item)
        persist(item, collection: .snippets, searchableText: "\(item.trigger) \(item.expansion)")
        return true
    }

    func createNote() -> UUID {
        let note = ScratchpadNote(
            id: UUID(),
            title: "Untitled note",
            body: "",
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        notes.insert(note, at: 0)
        persist(note, collection: .notes, searchableText: "\(note.title) \(note.body)")
        return note.id
    }

    func updateNote(id: UUID, title: String? = nil, body: String? = nil, isPinned: Bool? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if let title { notes[index].title = title }
        if let body { notes[index].body = body }
        if let isPinned { notes[index].isPinned = isPinned }
        notes[index].updatedAt = Date()
        let note = notes[index]
        persist(note, collection: .notes, searchableText: "\(note.title) \(note.body)")
        let previous = noteRevisions
            .filter { $0.noteID == id }
            .max { $0.createdAt < $1.createdAt }
        if ScratchpadRevisionPolicy().shouldCreateRevision(previous: previous, note: note, now: note.updatedAt) {
            let revision = ScratchpadRevision(
                id: UUID(),
                noteID: id,
                title: note.title,
                body: note.body,
                createdAt: note.updatedAt
            )
            noteRevisions.append(revision)
            persist(revision, collection: .noteRevisions, searchableText: "")
        }
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        removePersisted(id: id, collection: .notes)
        let revisions = noteRevisions.filter { $0.noteID == id }
        noteRevisions.removeAll { $0.noteID == id }
        for revision in revisions { removePersisted(id: revision.id, collection: .noteRevisions) }
    }

    func revisions(for noteID: UUID) -> [ScratchpadRevision] {
        noteRevisions.filter { $0.noteID == noteID }.sorted { $0.createdAt > $1.createdAt }
    }

    func restoreRevision(_ revision: ScratchpadRevision) {
        updateNote(id: revision.noteID, title: revision.title, body: revision.body)
    }

    private func commit(
        session: SourceSessionRecord,
        firstResult: TranscriptResultVersion
    ) async throws {
        guard let store else {
            throw SecureRecordStoreError.databaseOperation("Local storage is not ready.")
        }
        try await store.append(session: session, firstResult: firstResult)
        sourceSessions.insert(session, at: 0)
        resultVersions.insert(firstResult, at: 0)
        history.insert(
            try SessionResultProjection.history(session: session, results: [firstResult]),
            at: 0
        )
    }

    func removeHistoryRecord(id: UUID) {
        history.removeAll { $0.id == id }
        sourceSessions.removeAll { $0.id == id }
        resultVersions.removeAll { $0.sessionID == id }
        preferredResults.removeAll { $0.sessionID == id }
        retainedAudioSessionIDs.remove(id)
        let audioURL = MurmurV2Paths.retainedAudioDirectory.appendingPathComponent("\(id.uuidString).wav")
        try? FileManager.default.removeItem(at: audioURL)
        guard let store else { return }
        Task { @MainActor [weak self] in
            do {
                try await self?.retentionCoordinator?.deleteRecording(sessionID: id)
                try await store.deleteSession(id: id)
            } catch {
                self?.persistenceError = error.localizedDescription
                try? await self?.reloadVersionedHistory()
            }
        }
    }

    func purgeRetainedAudio() async {
        do {
            _ = try await retentionCoordinator?.purgeAll()
            retainedAudioSessionIDs = []
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func copyRecoveryText(sessionID: UUID) {
        guard let text = recoveryItems.first(where: { $0.id == sessionID })?.result?.finalTranscript
        else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func retainRecovery(sessionID: UUID) {
        recoveryItems.removeAll { $0.id == sessionID }
        guard let recoveryCoordinator else { return }
        Task { @MainActor [weak self] in
            do {
                try await recoveryCoordinator.clear(sessionID: sessionID)
            } catch {
                self?.persistenceError = error.localizedDescription
            }
        }
    }

    func deleteRecovery(sessionID: UUID) {
        recoveryItems.removeAll { $0.id == sessionID }
        guard let recoveryCoordinator else { return }
        Task { @MainActor [weak self] in
            do {
                try await recoveryCoordinator.deleteRecovery(sessionID: sessionID)
                self?.sourceSessions.removeAll { $0.id == sessionID }
                self?.resultVersions.removeAll { $0.sessionID == sessionID }
                self?.preferredResults.removeAll { $0.sessionID == sessionID }
                self?.history.removeAll { $0.id == sessionID }
                self?.retainedAudioSessionIDs.remove(sessionID)
            } catch {
                self?.persistenceError = error.localizedDescription
            }
        }
    }

    func versions(for sessionID: UUID) -> [TranscriptResultVersion] {
        resultVersions
            .filter { $0.sessionID == sessionID }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    func preferredResultID(for sessionID: UUID) -> UUID? {
        preferredResults.first(where: { $0.sessionID == sessionID })?.resultID
            ?? versions(for: sessionID).first?.id
    }

    func playRetainedAudio(sessionID: UUID) async {
        do {
            try await retainedAudioPlayback?.play(sessionID: sessionID)
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func stopRetainedAudio() {
        retainedAudioPlayback?.stop()
    }

    func retranscribe(sessionID: UUID, modelIdentifier: String) async {
        do {
            guard let store, let retentionCoordinator,
                  let parentID = preferredResultID(for: sessionID)
            else { throw RetainedRetranscriptionError.sessionNotFound }
            let model = try await exactModel(identifier: modelIdentifier)
            _ = try await RetainedAudioRetranscriptionService(
                retention: retentionCoordinator,
                store: store,
                engine: transcriptionEngine
            ).retranscribe(
                sessionID: sessionID,
                parentResultID: parentID,
                model: model,
                settings: settings,
                dictionary: dictionary,
                snippets: snippets
            )
            try await reloadVersionedHistory()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func retryRecovery(sessionID: UUID, modelIdentifier: String) async {
        do {
            guard let store, let retentionCoordinator,
                  let recoveryCoordinator,
                  let item = recoveryItems.first(where: { $0.id == sessionID })
            else { throw RetainedRetranscriptionError.sessionNotFound }
            let model = try await exactModel(identifier: modelIdentifier)
            _ = try await RetainedAudioRetranscriptionService(
                retention: retentionCoordinator,
                store: store,
                engine: transcriptionEngine
            ).recover(
                item: item,
                model: model,
                settings: settings,
                dictionary: dictionary,
                snippets: snippets
            )
            try await recoveryCoordinator.clear(sessionID: sessionID)
            recoveryItems.removeAll { $0.id == sessionID }
            try await reloadVersionedHistory()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func selectPreferredResult(sessionID: UUID, resultID: UUID) async {
        do {
            guard let store else {
                throw SecureRecordStoreError.databaseOperation("Local storage is not ready.")
            }
            let preference = PreferredResultRecord(
                sessionID: sessionID,
                resultID: resultID,
                updatedAt: Date()
            )
            try await store.savePreferredResult(preference)
            preferredResults.removeAll { $0.sessionID == sessionID }
            preferredResults.append(preference)
            history = try await store.fetchVersionedHistory()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func compareResults(
        baselineID: UUID,
        candidateID: UUID
    ) throws -> ResultVersionComparison {
        guard let baseline = resultVersions.first(where: { $0.id == baselineID }),
              let candidate = resultVersions.first(where: { $0.id == candidateID })
        else { throw RetainedRetranscriptionError.parentNotFound }
        return try ResultVersionComparisonService.compare(
            baseline: baseline,
            candidate: candidate
        )
    }

    func issueBundlePreview(
        sessionID: UUID,
        options: IssueBundleOptions
    ) async throws -> IssueBundlePreview {
        guard let issueBundleService else {
            throw SecureRecordStoreError.databaseOperation("Local storage is not ready.")
        }
        return try await issueBundleService.preview(
            request: try await issueBundleRequest(sessionID: sessionID),
            options: options
        )
    }

    func issueBundle(
        sessionID: UUID,
        options: IssueBundleOptions
    ) async throws -> Data {
        guard let issueBundleService else {
            throw SecureRecordStoreError.databaseOperation("Local storage is not ready.")
        }
        return try await issueBundleService.makeBundle(
            request: try await issueBundleRequest(sessionID: sessionID),
            options: options
        )
    }

    private func exactModel(identifier: String) async throws -> LocalWhisperModel {
        guard verifiedWhisperModelIdentifiers.contains(identifier) else {
            throw LocalTranscriptionError.modelUnavailable
        }
        let model = try await modelProvider.selectedModel(preferredIdentifier: identifier)
        guard model.identifier == identifier else { throw LocalTranscriptionError.modelUnavailable }
        return model
    }

    private func reloadVersionedHistory() async throws {
        guard let store else { return }
        sourceSessions = try await store.fetchSourceSessions()
        resultVersions = try await store.fetchResultVersions()
        preferredResults = try await store.fetchPreferredResults()
        history = try await store.fetchVersionedHistory()
        retainedAudioSessionIDs = Set(try await store.fetchRetainedAudio().map(\.id))
    }

    private func issueBundleRequest(sessionID: UUID) async throws -> IssueBundleRequest {
        guard let session = sourceSessions.first(where: { $0.id == sessionID }),
              let resultID = preferredResultID(for: sessionID),
              let result = resultVersions.first(where: { $0.id == resultID })
        else { throw RetainedRetranscriptionError.sessionNotFound }
        let model = try? await LocalWhisperModelVerificationCache.shared.verifiedModels(
            in: LocalWhisperModelCatalog()
        ).first(where: { $0.identifier == result.modelIdentifier })
        let recoveryFailure = recoveryItems.first(where: { $0.id == sessionID })?.journal.failureCode
        let failureCode = recoveryFailure ?? (result.insertionSucceeded ? nil : "insertion-failed")
        return IssueBundleRequest(
            session: session,
            result: result,
            failureCode: failureCode,
            modelSHA256: model?.sha256.isEmpty == false ? model?.sha256 : nil
        )
    }

    func setAudioRetentionPolicy(_ policy: AudioRetentionPolicy) {
        updateSettings { $0.audioRetentionPolicy = policy }
        guard let retentionCoordinator else { return }
        Task { @MainActor [weak self] in
            do {
                try await retentionCoordinator.apply(policy: policy, at: Date())
                let records = try await self?.store?.fetchRetainedAudio() ?? []
                self?.retainedAudioSessionIDs = Set(records.map(\.id))
            } catch {
                self?.persistenceError = error.localizedDescription
            }
        }
    }

    func removeDictionaryItem(id: UUID) {
        dictionary.removeAll { $0.id == id }
        removePersisted(id: id, collection: .dictionary)
    }

    func removeSnippet(id: UUID) {
        snippets.removeAll { $0.id == id }
        removePersisted(id: id, collection: .snippets)
    }

    func updateStyle(id: UUID, mutate: (inout WritingStyle) -> Void) {
        guard let index = styles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&styles[index])
        persist(styles[index], collection: .styles, searchableText: "\(styles[index].name) \(styles[index].instructions)")
    }

    func updateSettings(_ mutate: (inout MurmurSettingsRecord) -> Void) {
        let previousPreferredIdentifier = settings.preferredWhisperModelIdentifier
        guard let updated = settings.applyingChange(mutate) else { return }
        settings = updated
        flowBarController.apply(settings: settings)
        persist(settings, collection: .settings, searchableText: "")
        if previousPreferredIdentifier != updated.preferredWhisperModelIdentifier {
            scheduleTranscriptionWarmup()
        }
    }

    private func scheduleTranscriptionWarmup() {
        transcriptionWarmupTask?.cancel()

        let preferredIdentifier = settings.preferredWhisperModelIdentifier
        let transcriptionEngine = self.transcriptionEngine
        let modelProvider = self.modelProvider
        transcriptionWarmupTask = Task(priority: .utility) { [weak self] in
            do {
                // Refresh verification state before resolving a model so the Models page
                // reflects what is installed even when no model can be selected yet.
                let verifiedModels = try await LocalWhisperModelVerificationCache.shared.verifiedModels(
                    in: LocalWhisperModelCatalog()
                )
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    self?.verifiedWhisperModelIdentifiers = Set(verifiedModels.map(\.identifier))
                }
                let model = try await modelProvider.selectedModel(preferredIdentifier: preferredIdentifier)
                try await transcriptionEngine.warmup(model: model)
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error("Background transcription warmup failed: \(error.localizedDescription, privacy: .public)")
                // Warmup is speculative. Before onboarding installs a model there is
                // legitimately nothing to load, and the runtime is absent in builds
                // without a staged whisper.cpp — neither is a dictation failure, so
                // neither may surface in the Flow Bar the user has not invoked yet.
                if Self.isExpectedWarmupPrecondition(error) { return }
                await MainActor.run {
                    self?.dictationOrchestrator.recordBackgroundError(error.localizedDescription)
                }
            }
        }
    }

    /// Warmup failures that reflect a not-yet-configured install rather than a fault.
    nonisolated static func isExpectedWarmupPrecondition(_ error: Error) -> Bool {
        guard let error = error as? LocalTranscriptionError else { return false }
        switch error {
        case .modelUnavailable, .runtimeUnavailable: return true
        case .emptyTranscript, .incompleteTranscript, .processFailed: return false
        }
    }

    private static func makeTranscriptionEngine() -> any LocalTranscriptionEngine {
#if MURMUR_RESIDENT_WHISPER
        ResidentWhisperEngine()
#else
        WhisperCLITranscriptionEngine()
#endif
    }

    func encodedLibrary() throws -> Data {
        try MurmurLibraryTransferService().encode(
            MurmurLibraryBundle(dictionary: dictionary, snippets: snippets, styles: styles)
        )
    }

    func previewLibraryImport(_ data: Data) throws -> MurmurLibraryImportPreview {
        try MurmurLibraryTransferService().preview(
            data,
            existingDictionary: dictionary,
            existingSnippets: snippets
        )
    }

    func applyLibraryImport(_ preview: MurmurLibraryImportPreview) {
        for imported in preview.dictionaryToImport {
            let item = DictionaryItem(
                id: UUID(),
                spokenForm: imported.spokenForm,
                writtenForm: imported.writtenForm,
                context: imported.context,
                createdAt: Date()
            )
            dictionary.append(item)
            persist(item, collection: .dictionary, searchableText: "\(item.spokenForm) \(item.writtenForm)")
        }
        for imported in preview.snippetsToImport {
            let item = SnippetItem(
                id: UUID(),
                trigger: imported.trigger,
                expansion: imported.expansion,
                createdAt: Date()
            )
            snippets.append(item)
            persist(item, collection: .snippets, searchableText: "\(item.trigger) \(item.expansion)")
        }
        for imported in preview.stylesToImport {
            if let index = styles.firstIndex(where: {
                $0.context == imported.context && $0.name.caseInsensitiveCompare(imported.name) == .orderedSame
            }) {
                styles[index].instructions = imported.instructions
                styles[index].intensity = imported.intensity
                styles[index].isEnabled = imported.isEnabled
                persist(styles[index], collection: .styles, searchableText: "\(styles[index].name) \(styles[index].instructions)")
            } else {
                let style = WritingStyle(
                    id: UUID(),
                    context: imported.context,
                    name: imported.name,
                    instructions: imported.instructions,
                    intensity: imported.intensity,
                    isEnabled: imported.isEnabled
                )
                styles.append(style)
                persist(style, collection: .styles, searchableText: "\(style.name) \(style.instructions)")
            }
        }
    }

    func encryptedBackup(password: String) async throws -> Data {
        let payload = MurmurBackupPayload(
            exportedAt: Date(),
            history: history,
            dictionary: dictionary,
            snippets: snippets,
            styles: styles,
            notes: notes,
            revisions: noteRevisions,
            settings: settings,
            sourceSessions: sourceSessions,
            resultVersions: resultVersions,
            preferredResults: preferredResults
        )
        return try await Task.detached(priority: .userInitiated) {
            try MurmurBackupService().encrypt(payload, password: password)
        }.value
    }

    func restoreEncryptedBackup(_ data: Data, password: String) async throws {
        guard let store else { throw SecureRecordStoreError.databaseOperation("Local storage is not ready.") }
        let payload = try await Task.detached(priority: .userInitiated) {
            try MurmurBackupService().decrypt(data, password: password)
        }.value
        try await store.restore(payload)
        _ = try await retentionCoordinator?.purgeAll()
        for journal in try await store.fetchRecoveryJournals() {
            try await store.deleteRecoveryJournal(id: journal.id)
        }
        recoveryItems = []
        retainedAudioSessionIDs = []
        sourceSessions = try await store.fetchSourceSessions()
        resultVersions = try await store.fetchResultVersions()
        preferredResults = try await store.fetchPreferredResults()
        history = try await store.fetchVersionedHistory()
        dictionary = payload.dictionary
        snippets = payload.snippets
        styles = Self.mergeStyles(stored: payload.styles)
        let restoredStyleIDs = Set(payload.styles.map(\.id))
        for style in styles where restoredStyleIDs.contains(style.id) == false {
            try await store.save(
                style,
                collection: .styles,
                searchableText: "\(style.name) \(style.instructions)"
            )
        }
        notes = payload.notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
        noteRevisions = payload.revisions
        settings = payload.settings
        flowBarController.apply(settings: settings)
    }

    private func persist<Value: Codable & Identifiable & Sendable>(
        _ value: Value,
        collection: SecureRecordCollection,
        searchableText: String
    ) where Value.ID == UUID {
        guard let store else { return }
        Task { @MainActor [weak self] in
            do {
                try await store.save(value, collection: collection, searchableText: searchableText)
            } catch {
                self?.persistenceError = error.localizedDescription
            }
        }
    }

    private func removePersisted(id: UUID, collection: SecureRecordCollection) {
        guard let store else { return }
        Task { @MainActor [weak self] in
            do {
                try await store.delete(id: id, collection: collection)
            } catch {
                self?.persistenceError = error.localizedDescription
            }
        }
    }

    private static let defaultStyles: [WritingStyle] = [
        WritingStyle(id: UUID(), context: .messaging, name: "Conversational", instructions: "Clear, warm, and concise.", intensity: 0.5, isEnabled: true),
        WritingStyle(id: UUID(), context: .email, name: "Professional", instructions: "Polished and direct without sounding stiff.", intensity: 0.6, isEnabled: true),
        WritingStyle(id: UUID(), context: .document, name: "Structured", instructions: "Organize longer thoughts into readable paragraphs.", intensity: 0.5, isEnabled: true),
        WritingStyle(id: UUID(), context: .browser, name: "Form-ready", instructions: "Use direct complete answers suited to browser forms.", intensity: 0.4, isEnabled: true),
        WritingStyle(id: UUID(), context: .code, name: "Code-safe", instructions: "Preserve identifiers, syntax, and formatting exactly.", intensity: 0.2, isEnabled: true),
        WritingStyle(id: UUID(), context: .terminal, name: "Terminal-safe", instructions: "Preserve commands, paths, flags, and shell syntax exactly.", intensity: 0.1, isEnabled: true),
        WritingStyle(id: UUID(), context: .general, name: "Balanced", instructions: "Natural, readable, and faithful to the speaker.", intensity: 0.5, isEnabled: true),
    ]

    private static func mergeStyles(stored: [WritingStyle]) -> [WritingStyle] {
        var result = stored
        for style in defaultStyles where result.contains(where: {
            $0.context == style.context && $0.name.caseInsensitiveCompare(style.name) == .orderedSame
        }) == false {
            result.append(style)
        }
        return result.sorted {
            let lhsIndex = WritingContext.allCases.firstIndex(of: $0.context) ?? Int.max
            let rhsIndex = WritingContext.allCases.firstIndex(of: $1.context) ?? Int.max
            return lhsIndex < rhsIndex
        }
    }
}
