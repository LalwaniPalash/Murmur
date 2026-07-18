import AppKit
import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var selectedDestination: HubDestination = .home
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

    let permissionCenter = PermissionCenter()
    let modelInstaller = WhisperModelInstaller()
    private var store: SecureRecordStore?
    private let shortcutMonitor = GlobalShortcutMonitor()
    private var shortcutsStarted = false
    private var subscriptions: Set<AnyCancellable> = []

    lazy var dictationOrchestrator = DictationOrchestrator(
        audioInput: SystemAudioInput(),
        transcriptionEngine: WhisperCLITranscriptionEngine(),
        modelProvider: InstalledWhisperModelProvider(),
        insertionService: TextInsertionCoordinator(),
        configuration: { [weak self] in
            DictationRuntimeConfiguration(settings: self?.settings ?? .default)
        },
        personalization: { [weak self] in
            (self?.dictionary ?? [], self?.snippets ?? [])
        },
        historyHandler: { [weak self] record in
            self?.addHistoryRecord(record)
        }
    )

    lazy var flowBarController = FlowBarController(orchestrator: dictationOrchestrator)

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "Murmur.v2.onboardingCompleted")
        configureShortcuts()
        modelInstaller.$state
            .sink { [weak self] state in
                guard case .installed(let manifest) = state else { return }
                Task { @MainActor in
                    guard let self else { return }
                    await self.refreshVerifiedWhisperModels()
                    self.activateWhisperModel(identifier: manifest.id)
                }
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
            let key = try await KeychainMasterKeyStore.shared.loadOrCreateKey()
            let store = try SecureRecordStore(url: MurmurV2Paths.databaseURL, key: key)
            self.store = store

            async let storedHistory: [TranscriptRecord] = store.fetch(collection: .history)
            async let storedDictionary: [DictionaryItem] = store.fetch(collection: .dictionary)
            async let storedSnippets: [SnippetItem] = store.fetch(collection: .snippets)
            async let storedStyles: [WritingStyle] = store.fetch(collection: .styles)
            async let storedNotes: [ScratchpadNote] = store.fetch(collection: .notes)
            async let storedRevisions: [ScratchpadRevision] = store.fetch(collection: .noteRevisions)
            async let storedSettings: [MurmurSettingsRecord] = store.fetch(collection: .settings, limit: 1)
            let loaded = try await (
                storedHistory,
                storedDictionary,
                storedSnippets,
                storedStyles,
                storedNotes,
                storedRevisions,
                storedSettings
            )
            history = loaded.0
            dictionary = loaded.1
            snippets = loaded.2
            styles = Self.mergeStyles(stored: loaded.3)
            let storedStyleIDs = Set(loaded.3.map(\.id))
            for style in styles where storedStyleIDs.contains(style.id) == false {
                try await store.save(
                    style,
                    collection: .styles,
                    searchableText: "\(style.name) \(style.instructions)"
                )
            }
            notes = loaded.4
            noteRevisions = loaded.5
            settings = loaded.6.first ?? .default
            await refreshVerifiedWhisperModels()
            isLoaded = true
            permissionCenter.refresh()
            _ = flowBarController
            flowBarController.apply(settings: settings)
            startShortcutsIfPossible()
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
        shortcutMonitor.onCommandReleased = { [weak self] in
            Task { await self?.dictationOrchestrator.finish() }
        }
        shortcutMonitor.onCancel = { [weak self] in
            Task { await self?.dictationOrchestrator.cancel() }
        }
    }

    private func startShortcutsIfPossible() {
        guard shortcutsStarted == false, permissionCenter.accessibilityGranted else { return }
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

    func removeDictionaryItems(at offsets: IndexSet) {
        let items = offsets.compactMap { dictionary.indices.contains($0) ? dictionary[$0] : nil }
        dictionary.remove(atOffsets: offsets)
        for item in items { removePersisted(id: item.id, collection: .dictionary) }
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

    func removeSnippets(at offsets: IndexSet) {
        let items = offsets.compactMap { snippets.indices.contains($0) ? snippets[$0] : nil }
        snippets.remove(atOffsets: offsets)
        for item in items { removePersisted(id: item.id, collection: .snippets) }
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

    func addHistoryRecord(_ record: TranscriptRecord) {
        history.insert(record, at: 0)
        persist(record, collection: .history, searchableText: "\(record.sourceApplication) \(record.text)")
    }

    func removeHistoryRecord(id: UUID) {
        history.removeAll { $0.id == id }
        removePersisted(id: id, collection: .history)
        let audioURL = MurmurV2Paths.retainedAudioDirectory.appendingPathComponent("\(id.uuidString).wav")
        try? FileManager.default.removeItem(at: audioURL)
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
        guard let updated = settings.applyingChange(mutate) else { return }
        settings = updated
        flowBarController.apply(settings: settings)
        persist(settings, collection: .settings, searchableText: "")
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
            settings: settings
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
        history = payload.history.sorted { $0.createdAt > $1.createdAt }
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
