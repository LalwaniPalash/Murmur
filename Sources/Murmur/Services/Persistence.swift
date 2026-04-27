import AppKit
import Combine
import CryptoKit
import Foundation
import Security

enum MurmurError: LocalizedError {
    case missingHomeDirectory
    case keychainFailure(OSStatus)
    case malformedEncryptedPayload
    case modelImportCancelled
    case developmentKeyFailure

    var errorDescription: String? {
        switch self {
        case .missingHomeDirectory:
            "Application Support is unavailable."
        case .keychainFailure(let status):
            "Keychain access failed with status \(status)."
        case .malformedEncryptedPayload:
            "The encrypted local store could not be decoded."
        case .modelImportCancelled:
            "Model import was cancelled."
        case .developmentKeyFailure:
            "The local development encryption key could not be created."
        }
    }
}

enum AppPaths {
    static let bundleIdentifier = "com.murmur.app"

    static var applicationSupportDirectory: URL {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to resolve Application Support directory.")
        }

        let root = directory.appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static var secureStoreDirectory: URL {
        let url = applicationSupportDirectory.appendingPathComponent("SecureStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var diagnosticsDirectory: URL {
        let url = applicationSupportDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var runtimesDirectory: URL {
        let url = applicationSupportDirectory.appendingPathComponent("Runtimes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var whisperModelsDirectory: URL {
        let url = applicationSupportDirectory.appendingPathComponent("Models/Whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var llamaModelsDirectory: URL {
        let url = applicationSupportDirectory.appendingPathComponent("Models/Llama", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var developmentMasterKeyURL: URL {
        secureStoreDirectory.appendingPathComponent("master.key")
    }

    static var personalizationURL: URL { secureStoreDirectory.appendingPathComponent("personalization.bin") }
    static var historyURL: URL { secureStoreDirectory.appendingPathComponent("history.bin") }
    static var notesURL: URL { secureStoreDirectory.appendingPathComponent("notes.bin") }
    static var settingsURL: URL { secureStoreDirectory.appendingPathComponent("settings.bin") }
    static var modelsURL: URL { secureStoreDirectory.appendingPathComponent("models.bin") }
}

actor SecretMaterialStore {
    static let shared = SecretMaterialStore()

    private var cachedMasterKeyData: Data?

    private init() {}

    func secretData(for account: String) throws -> Data {
        _ = account
        if let cachedMasterKeyData {
            return cachedMasterKeyData
        }

#if DEBUG
        let data = try loadOrCreateDevelopmentKey()
#else
        let data = try loadOrCreateKeychainKey(account: "master-store-key")
#endif
        cachedMasterKeyData = data
        return data
    }

    private func loadOrCreateKeychainKey(account: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: AppPaths.bundleIdentifier,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return data
        }

        guard status == errSecItemNotFound else {
            throw MurmurError.keychainFailure(status)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let generationStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard generationStatus == errSecSuccess else {
            throw MurmurError.keychainFailure(generationStatus)
        }

        let data = Data(bytes)
        let insertQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: AppPaths.bundleIdentifier,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw MurmurError.keychainFailure(addStatus)
        }

        return data
    }

    private func loadOrCreateDevelopmentKey() throws -> Data {
        let url = AppPaths.developmentMasterKeyURL
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let generationStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard generationStatus == errSecSuccess else {
            throw MurmurError.developmentKeyFailure
        }

        let data = Data(bytes)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return data
    }
}

actor EncryptedJSONStore<Value: Codable & Sendable> {
    private let url: URL
    private let defaultValue: Value
    private let keyAlias: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL, defaultValue: Value, keyAlias: String) {
        self.url = url
        self.defaultValue = defaultValue
        self.keyAlias = keyAlias
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() async throws -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return defaultValue
        }

        let encrypted = try Data(contentsOf: url)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: encrypted) else {
            throw MurmurError.malformedEncryptedPayload
        }

        let decrypted = try AES.GCM.open(sealedBox, using: try await secretKey())
        return try decoder.decode(Value.self, from: decrypted)
    }

    func save(_ value: Value) async throws {
        let data = try encoder.encode(value)
        let sealedBox = try AES.GCM.seal(data, using: try await secretKey())
        guard let combined = sealedBox.combined else {
            throw MurmurError.malformedEncryptedPayload
        }
        try combined.write(to: url, options: .atomic)
    }

    private func secretKey() async throws -> SymmetricKey {
        SymmetricKey(data: try await SecretMaterialStore.shared.secretData(for: keyAlias))
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var snapshot: SettingsSnapshot = .default

    private let store = EncryptedJSONStore(url: AppPaths.settingsURL, defaultValue: SettingsSnapshot.default, keyAlias: "settings-store")

    func load() async {
        do {
            snapshot = try await store.load()
        } catch {
            NSLog("Failed to load settings: \(error.localizedDescription)")
        }
    }

    func update(_ mutate: (inout SettingsSnapshot) -> Void) {
        mutate(&snapshot)
        Task {
            do {
                try await store.save(snapshot)
            } catch {
                NSLog("Failed to save settings: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
final class PersonalizationStore: ObservableObject {
    @Published private(set) var snapshot: PersonalizationSnapshot = .default

    private let store = EncryptedJSONStore(url: AppPaths.personalizationURL, defaultValue: PersonalizationSnapshot.default, keyAlias: "personalization-store")

    func load() async {
        do {
            snapshot = try await store.load()
        } catch {
            NSLog("Failed to load personalization: \(error.localizedDescription)")
        }
    }

    func addSnippet(trigger: String, expansion: String) {
        snapshot.snippets.append(Snippet(id: UUID(), trigger: trigger, expansion: expansion))
        persist()
    }

    func removeSnippet(_ snippet: Snippet) {
        snapshot.snippets.removeAll { $0.id == snippet.id }
        persist()
    }

    func addDictionaryEntry(phrase: String, replacement: String, context: AppWritingContext?) {
        snapshot.dictionaryEntries.append(DictionaryEntry(id: UUID(), phrase: phrase, replacement: replacement, context: context))
        persist()
    }

    func removeDictionaryEntry(_ entry: DictionaryEntry) {
        snapshot.dictionaryEntries.removeAll { $0.id == entry.id }
        persist()
    }

    func upsertStyleProfile(_ profile: StyleProfile) {
        if let index = snapshot.styleProfiles.firstIndex(where: { $0.id == profile.id }) {
            snapshot.styleProfiles[index] = profile
        } else {
            snapshot.styleProfiles.append(profile)
        }
        persist()
    }

    func matchingSnippet(for text: String) -> Snippet? {
        snapshot.snippets.first { $0.trigger.compare(text.trimmingCharacters(in: .whitespacesAndNewlines), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    private func persist() {
        let snapshot = snapshot
        Task {
            do {
                try await store.save(snapshot)
            } catch {
                NSLog("Failed to save personalization: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let store = EncryptedJSONStore(url: AppPaths.historyURL, defaultValue: [HistoryEntry](), keyAlias: "history-store")

    var stats: UsageStats {
        guard !entries.isEmpty else {
            return .empty
        }

        let totalWords = entries.reduce(0) { partial, entry in
            partial + entry.finalText.split(whereSeparator: \.isWhitespace).count
        }

        let totalMinutes = entries.reduce(0.0) { partial, entry in
            partial + max(entry.createdAt.timeIntervalSinceReferenceDate - entry.createdAt.addingTimeInterval(-60).timeIntervalSinceReferenceDate, 0) / 60
        }

        let averageWPM = totalMinutes > 0 ? Double(totalWords) / max(totalMinutes, 1) : 0

        return UsageStats(
            totalWords: totalWords,
            averageWordsPerMinute: averageWPM,
            totalSessions: entries.count,
            lastSessionAt: entries.first?.createdAt
        )
    }

    func load() async {
        do {
            entries = try await store.load().sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            NSLog("Failed to load history: \(error.localizedDescription)")
        }
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        let entries = entries
        Task {
            do {
                try await store.save(entries)
            } catch {
                NSLog("Failed to save history: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [NoteDocument] = []
    @Published var selectedNoteID: UUID?

    private let store = EncryptedJSONStore(url: AppPaths.notesURL, defaultValue: [NoteDocument](), keyAlias: "notes-store")

    func load() async {
        do {
            notes = try await store.load().sorted(by: { $0.updatedAt > $1.updatedAt })
            if selectedNoteID == nil {
                selectedNoteID = notes.first?.id
            }
            if notes.isEmpty {
                createNote()
            }
        } catch {
            NSLog("Failed to load notes: \(error.localizedDescription)")
            createNote()
        }
    }

    func createNote() {
        let now = Date()
        let note = NoteDocument(id: UUID(), title: "Quick Note", body: "", createdAt: now, updatedAt: now)
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        persist()
    }

    func updateSelected(body: String) {
        guard let selectedNoteID, let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else {
            return
        }

        notes[index].body = body
        notes[index].updatedAt = Date()
        notes[index].title = body
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(40)
            .description
            .nonEmpty ?? "Quick Note"
        notes.sort(by: { $0.updatedAt > $1.updatedAt })
        persist()
    }

    func delete(_ note: NoteDocument) {
        notes.removeAll { $0.id == note.id }
        if selectedNoteID == note.id {
            selectedNoteID = notes.first?.id
        }
        if notes.isEmpty {
            createNote()
        } else {
            persist()
        }
    }

    var selectedNote: NoteDocument? {
        guard let selectedNoteID else { return notes.first }
        return notes.first(where: { $0.id == selectedNoteID })
    }

    private func persist() {
        let notes = notes
        Task {
            do {
                try await store.save(notes)
            } catch {
                NSLog("Failed to save notes: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var descriptors: [ModelDescriptor] = []
    @Published private(set) var runtimes: [RuntimeInstallation] = RuntimeInventorySnapshot.default.runtimes

    private let store = EncryptedJSONStore(url: AppPaths.modelsURL, defaultValue: RuntimeInventorySnapshot.default, keyAlias: "models-store")

    func load() async {
        do {
            let persisted = try await store.load()
            descriptors = reconcileCatalogs(with: persisted.models)
            runtimes = persisted.runtimes.isEmpty ? RuntimeInventorySnapshot.default.runtimes : persisted.runtimes
        } catch {
            descriptors = RuntimeInventorySnapshot.default.models
            runtimes = RuntimeInventorySnapshot.default.runtimes
            NSLog("Failed to load models: \(error.localizedDescription)")
        }
        refreshInstalledWhisperModels()
        refreshInstalledLlamaModels()
    }

    func whisperModels() -> [ModelDescriptor] {
        descriptors
            .filter { $0.runtime == .whisperCPP && $0.modelIdentifier != nil }
            .sorted { ($0.modelIdentifier ?? "") < ($1.modelIdentifier ?? "") }
    }

    func llamaModels() -> [ModelDescriptor] {
        descriptors
            .filter { $0.runtime == .llamaCPP && $0.modelIdentifier != nil }
            .sorted { ($0.modelIdentifier ?? "") < ($1.modelIdentifier ?? "") }
    }

    func preferredWhisperModel(using settings: SettingsSnapshot) -> ModelDescriptor? {
        preferredModel(
            for: .whisperCPP,
            preferredIdentifier: settings.preferredWhisperModelIdentifier,
            recommendedIdentifier: WhisperModelPreset.recommended.rawValue
        )
    }

    func preferredLlamaModel(using settings: SettingsSnapshot) -> ModelDescriptor? {
        preferredModel(
            for: .llamaCPP,
            preferredIdentifier: settings.preferredLlamaModelIdentifier,
            recommendedIdentifier: LlamaModelPreset.recommended.rawValue
        )
    }

    func importWhisperModelFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import Whisper Model"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let modelIdentifier = WhisperModelPreset.allCases.first(where: { url.lastPathComponent == $0.fileName })?.rawValue
        upsertModel(
            ModelDescriptor(
                id: existingModelID(for: modelIdentifier, runtime: .whisperCPP),
                name: modelIdentifier ?? url.deletingPathExtension().lastPathComponent,
                runtime: .whisperCPP,
                modelIdentifier: modelIdentifier,
                localeIdentifier: WhisperModelPreset.allCases.first(where: { $0.rawValue == modelIdentifier })?.localeIdentifier,
                status: .imported,
                storagePath: url.path,
                notes: "Imported locally by the user."
            )
        )
        persist()
    }

    func importLlamaModelFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import Llama Model"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let modelIdentifier = LlamaModelPreset.allCases.first(where: { url.lastPathComponent == $0.fileName })?.rawValue
        upsertModel(
            ModelDescriptor(
                id: existingModelID(for: modelIdentifier, runtime: .llamaCPP),
                name: LlamaModelPreset(rawValue: modelIdentifier ?? "")?.displayName ?? url.deletingPathExtension().lastPathComponent,
                runtime: .llamaCPP,
                modelIdentifier: modelIdentifier,
                localeIdentifier: nil,
                status: .imported,
                storagePath: url.path,
                notes: "Imported locally by the user."
            )
        )
        persist()
    }

    func importModelFromPanel(runtime: ModelDescriptor.Runtime) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import Model"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        descriptors.append(
            ModelDescriptor(
                id: UUID(),
                name: url.lastPathComponent,
                runtime: runtime,
                modelIdentifier: nil,
                localeIdentifier: nil,
                status: .imported,
                storagePath: url.path,
                notes: "Imported locally by the user."
            )
        )
        persist()
    }

    func markWhisperModelInstalling(_ preset: WhisperModelPreset) {
        updateWhisperModel(preset) { descriptor in
            descriptor.status = .installing
            descriptor.notes = "\(preset.sizeLabel) • Installing into \(AppPaths.whisperModelsDirectory.path)"
        }
    }

    func markWhisperModelInstalled(_ preset: WhisperModelPreset, path: String) {
        updateWhisperModel(preset) { descriptor in
            descriptor.status = .ready
            descriptor.storagePath = path
            descriptor.notes = "\(preset.sizeLabel) • Installed for whisper.cpp"
        }
    }

    func markWhisperModelFailed(_ preset: WhisperModelPreset, message: String) {
        updateWhisperModel(preset) { descriptor in
            descriptor.status = .needsDownload
            descriptor.storagePath = nil
            descriptor.notes = "\(preset.sizeLabel) • \(message)"
        }
    }

    func markWhisperModelCancelled(_ preset: WhisperModelPreset) {
        updateWhisperModel(preset) { descriptor in
            descriptor.status = .needsDownload
            descriptor.storagePath = nil
            descriptor.notes = "\(preset.sizeLabel) • Installation cancelled."
        }
    }

    func markLlamaModelInstalling(_ preset: LlamaModelPreset) {
        updateLlamaModel(preset) { descriptor in
            descriptor.status = .installing
            descriptor.notes = "\(preset.sizeLabel) • Installing into \(AppPaths.llamaModelsDirectory.path)"
        }
    }

    func markLlamaModelInstalled(_ preset: LlamaModelPreset, path: String) {
        updateLlamaModel(preset) { descriptor in
            descriptor.status = .ready
            descriptor.storagePath = path
            descriptor.notes = "\(preset.sizeLabel) • Installed for llama.cpp"
        }
    }

    func markLlamaModelFailed(_ preset: LlamaModelPreset, message: String) {
        updateLlamaModel(preset) { descriptor in
            descriptor.status = .needsDownload
            descriptor.storagePath = nil
            descriptor.notes = "\(preset.sizeLabel) • \(message)"
        }
    }

    func markLlamaModelCancelled(_ preset: LlamaModelPreset) {
        updateLlamaModel(preset) { descriptor in
            descriptor.status = .needsDownload
            descriptor.storagePath = nil
            descriptor.notes = "\(preset.sizeLabel) • Installation cancelled."
        }
    }

    func deleteWhisperModel(_ preset: WhisperModelPreset) {
        deleteModelFileIfManaged(
            at: descriptors.first {
                $0.modelIdentifier == preset.rawValue && $0.runtime == .whisperCPP
            }?.storagePath,
            managedDirectory: AppPaths.whisperModelsDirectory
        )
        updateWhisperModel(preset) { descriptor in
            descriptor.status = .needsDownload
            descriptor.storagePath = nil
            descriptor.notes = "\(preset.sizeLabel) • \(preset.summary)"
        }
    }

    func deleteLlamaModel(_ preset: LlamaModelPreset) {
        deleteModelFileIfManaged(
            at: descriptors.first {
                $0.modelIdentifier == preset.rawValue && $0.runtime == .llamaCPP
            }?.storagePath,
            managedDirectory: AppPaths.llamaModelsDirectory
        )
        updateLlamaModel(preset) { descriptor in
            descriptor.status = .needsDownload
            descriptor.storagePath = nil
            descriptor.notes = "\(preset.sizeLabel) • \(preset.summary)"
        }
    }

    func updateRuntime(_ kind: RuntimeInstallation.Kind, mutate: (inout RuntimeInstallation) -> Void) {
        guard let index = runtimes.firstIndex(where: { $0.kind == kind }) else {
            return
        }
        mutate(&runtimes[index])
        persist()
    }

    func refreshInstalledWhisperModels() {
        var didChange = false
        descriptors = reconcileCatalogs(with: descriptors).map { descriptor in
            guard descriptor.runtime == .whisperCPP, let modelIdentifier = descriptor.modelIdentifier else {
                return descriptor
            }

            var copy = descriptor
            let modelURL = AppPaths.whisperModelsDirectory.appendingPathComponent("ggml-\(modelIdentifier).bin")
            if FileManager.default.fileExists(atPath: modelURL.path) {
                copy.status = .ready
                copy.storagePath = modelURL.path
                copy.notes = "\(WhisperModelPreset(rawValue: modelIdentifier)?.sizeLabel ?? "") • Installed for whisper.cpp".trimmingCharacters(in: .whitespaces)
            } else if descriptor.status == .ready || descriptor.status == .installing {
                copy.status = .needsDownload
                copy.storagePath = nil
            }
            didChange = didChange || copy != descriptor
            return copy
        }
        if didChange {
            persist()
        }
    }

    func refreshInstalledLlamaModels() {
        var didChange = false
        descriptors = reconcileCatalogs(with: descriptors).map { descriptor in
            guard descriptor.runtime == .llamaCPP, let modelIdentifier = descriptor.modelIdentifier else {
                return descriptor
            }

            var copy = descriptor
            if let preset = LlamaModelPreset(rawValue: modelIdentifier) {
                let modelURL = AppPaths.llamaModelsDirectory.appendingPathComponent(preset.fileName)
                if FileManager.default.fileExists(atPath: modelURL.path) {
                    copy.status = .ready
                    copy.storagePath = modelURL.path
                    copy.notes = "\(preset.sizeLabel) • Installed for llama.cpp"
                } else if descriptor.status == .ready || descriptor.status == .installing {
                    copy.status = .needsDownload
                    copy.storagePath = nil
                }
            }

            didChange = didChange || copy != descriptor
            return copy
        }
        if didChange {
            persist()
        }
    }

    private func reconcileCatalogs(with models: [ModelDescriptor]) -> [ModelDescriptor] {
        let catalog = reconcileWhisperCatalog(with: models) + reconcileLlamaCatalog(with: models)
        let catalogRuntimePairs = Set(catalog.compactMap { descriptor in
            descriptor.modelIdentifier.map { "\($0)::\(descriptor.runtime.rawValue)" }
        })
        let customModels = models.filter { descriptor in
            guard let modelIdentifier = descriptor.modelIdentifier else {
                return true
            }
            return catalogRuntimePairs.contains("\(modelIdentifier)::\(descriptor.runtime.rawValue)") == false
        }
        return catalog + customModels
    }

    private func reconcileWhisperCatalog(with models: [ModelDescriptor]) -> [ModelDescriptor] {
        let existingPairs: [(String, ModelDescriptor)] = models.compactMap { descriptor in
            guard descriptor.runtime == .whisperCPP, let identifier = descriptor.modelIdentifier else {
                return nil
            }
            return (identifier, descriptor)
        }
        let existingByIdentifier = Dictionary(
            uniqueKeysWithValues: existingPairs
        )

        let catalog = WhisperModelPreset.allCases.map { preset -> ModelDescriptor in
            if var existing = existingByIdentifier[preset.rawValue] {
                existing.name = preset.displayName
                existing.runtime = .whisperCPP
                existing.modelIdentifier = preset.rawValue
                existing.localeIdentifier = preset.localeIdentifier
                if existing.notes.isEmpty {
                    existing.notes = "\(preset.sizeLabel) • \(preset.summary)"
                }
                return existing
            }

            return ModelDescriptor(
                id: UUID(),
                name: preset.displayName,
                runtime: .whisperCPP,
                modelIdentifier: preset.rawValue,
                localeIdentifier: preset.localeIdentifier,
                status: .needsDownload,
                storagePath: nil,
                notes: "\(preset.sizeLabel) • \(preset.summary)"
            )
        }
        return catalog
    }

    private func reconcileLlamaCatalog(with models: [ModelDescriptor]) -> [ModelDescriptor] {
        let existingPairs: [(String, ModelDescriptor)] = models.compactMap { descriptor in
            guard descriptor.runtime == .llamaCPP, let identifier = descriptor.modelIdentifier else {
                return nil
            }
            return (identifier, descriptor)
        }
        let existingByIdentifier = Dictionary(
            uniqueKeysWithValues: existingPairs
        )

        return LlamaModelPreset.allCases.map { preset in
            if var existing = existingByIdentifier[preset.rawValue] {
                existing.name = preset.displayName
                existing.runtime = .llamaCPP
                existing.modelIdentifier = preset.rawValue
                if existing.notes.isEmpty {
                    existing.notes = "\(preset.sizeLabel) • \(preset.summary)"
                }
                return existing
            }

            return ModelDescriptor(
                id: UUID(),
                name: preset.displayName,
                runtime: .llamaCPP,
                modelIdentifier: preset.rawValue,
                localeIdentifier: nil,
                status: .needsDownload,
                storagePath: nil,
                notes: "\(preset.sizeLabel) • \(preset.summary)"
            )
        }
    }

    private func updateWhisperModel(_ preset: WhisperModelPreset, mutate: (inout ModelDescriptor) -> Void) {
        guard let index = descriptors.firstIndex(where: { $0.modelIdentifier == preset.rawValue && $0.runtime == .whisperCPP }) else {
            return
        }
        mutate(&descriptors[index])
        persist()
    }

    private func updateLlamaModel(_ preset: LlamaModelPreset, mutate: (inout ModelDescriptor) -> Void) {
        guard let index = descriptors.firstIndex(where: { $0.modelIdentifier == preset.rawValue && $0.runtime == .llamaCPP }) else {
            return
        }
        mutate(&descriptors[index])
        persist()
    }

    private func upsertModel(_ descriptor: ModelDescriptor) {
        if let identifier = descriptor.modelIdentifier,
           let index = descriptors.firstIndex(where: { $0.modelIdentifier == identifier && $0.runtime == descriptor.runtime }) {
            descriptors[index] = descriptor
            return
        }

        if let index = descriptors.firstIndex(where: { $0.id == descriptor.id }) {
            descriptors[index] = descriptor
        } else {
            descriptors.append(descriptor)
        }
    }

    private func deleteModelFileIfManaged(at path: String?, managedDirectory: URL) {
        guard let path else { return }

        let modelURL = URL(fileURLWithPath: path).standardizedFileURL
        let managedRoot = managedDirectory.standardizedFileURL.path
        guard modelURL.path == managedRoot || modelURL.path.hasPrefix("\(managedRoot)/") else {
            return
        }

        try? FileManager.default.removeItem(at: modelURL)
    }

    private func existingModelID(for modelIdentifier: String?, runtime: ModelDescriptor.Runtime) -> UUID {
        if let modelIdentifier,
           let existing = descriptors.first(where: { $0.modelIdentifier == modelIdentifier && $0.runtime == runtime }) {
            return existing.id
        }
        return UUID()
    }

    private func preferredModel(
        for runtime: ModelDescriptor.Runtime,
        preferredIdentifier: String,
        recommendedIdentifier: String
    ) -> ModelDescriptor? {
        let matchingRuntime = descriptors.filter { $0.runtime == runtime }

        let candidates = [
            matchingRuntime.first(where: { $0.modelIdentifier == preferredIdentifier && ($0.status == .ready || $0.status == .imported) }),
            matchingRuntime.first(where: { $0.modelIdentifier == recommendedIdentifier && ($0.status == .ready || $0.status == .imported) }),
            matchingRuntime.first(where: { $0.status == .ready || $0.status == .imported })
        ]

        return candidates.compactMap { $0 }.first
    }

    private func persist() {
        let snapshot = RuntimeInventorySnapshot(runtimes: runtimes, models: descriptors)
        Task {
            do {
                try await store.save(snapshot)
            } catch {
                NSLog("Failed to save model descriptors: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
final class DiagnosticsExporter {
    func export(
        permissions: AppPermissions,
        activeMode: DictationMode?,
        settings: SettingsSnapshot,
        historyEntries: [HistoryEntry],
        notes: [NoteDocument],
        runtimes: [RuntimeInstallation],
        models: [ModelDescriptor],
        redactingContent: Bool
    ) throws -> URL {
        let snapshot = DiagnosticsSnapshot(
            exportedAt: Date(),
            redacted: redactingContent,
            permissions: permissions,
            activeMode: activeMode,
            cleanupLevel: settings.cleanupLevel,
            localeIdentifier: settings.localeIdentifier,
            historyCount: historyEntries.count,
            noteCount: notes.count,
            runtimes: runtimes,
            modelStatuses: models,
            latestHistory: historyEntries.prefix(20).map { entry in
                guard redactingContent else { return entry }
                var copy = entry
                copy.finalText = "[REDACTED]"
                copy.recoveryMetadata = nil
                return copy
            }
        )

        let fileURL = AppPaths.diagnosticsDirectory.appendingPathComponent(
            "murmur-diagnostics-\(Int(Date().timeIntervalSince1970)).json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
