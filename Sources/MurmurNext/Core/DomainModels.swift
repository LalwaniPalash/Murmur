import Foundation

/// Four panel divisions. Settings lives in the standard macOS Settings window rather
/// than duplicating itself as a destination with its own inner navigation, and the
/// shortcut legend is engraved on the panel instead of occupying a Help page.
enum HubDestination: String, CaseIterable, Identifiable, Sendable {
    case record
    case vocabulary
    case engine
    case scratchpad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .record: "Record"
        case .vocabulary: "Vocabulary"
        case .engine: "Engine"
        case .scratchpad: "Scratchpad"
        }
    }

    var systemImage: String {
        switch self {
        case .record: "text.alignleft"
        case .vocabulary: "character.book.closed"
        case .engine: "cpu"
        case .scratchpad: "square.and.pencil"
        }
    }
}

enum DictationPhase: String, Codable, Equatable, Sendable {
    case idle
    case calibrating
    case listening
    case finalizing
    case inserting
    case completed
    case failed
    case cancelled
}

enum DictationMode: String, Codable, Equatable, Sendable {
    case pushToTalk
    case handsFree
    case command
}

enum WritingContext: String, Codable, CaseIterable, Identifiable, Sendable {
    case messaging
    case email
    case document
    case browser
    case code
    case terminal
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .messaging: "Messages"
        case .email: "Email"
        case .document: "Documents"
        case .browser: "Browser forms"
        case .code: "Code"
        case .terminal: "Terminal"
        case .general: "Everywhere else"
        }
    }
}

struct DictationSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var mode: DictationMode
    let startedAt: Date
    var endedAt: Date?
    var targetBundleIdentifier: String?
    var provisionalText: String
    var finalText: String
    var phase: DictationPhase
}

struct TranscriptRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let sourceApplication: String
    let sourceBundleIdentifier: String?
    let context: WritingContext
    let mode: DictationMode
    let text: String
    let duration: TimeInterval
    let wordsPerMinute: Double
    let insertionSucceeded: Bool
}

struct UsageSummary: Equatable, Sendable {
    var words: Int
    var sessions: Int
    var averageWordsPerMinute: Double
    var daysUsed: Int

    static let empty = UsageSummary(words: 0, sessions: 0, averageWordsPerMinute: 0, daysUsed: 0)
}

struct DictionaryItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var spokenForm: String
    var writtenForm: String
    var context: WritingContext?
    var createdAt: Date
}

struct SnippetItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var trigger: String
    var expansion: String
    var createdAt: Date
}

struct WritingStyle: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var context: WritingContext
    var name: String
    var instructions: String
    var intensity: Double
    var isEnabled: Bool
}

struct ScratchpadNote: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct ScratchpadRevision: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let noteID: UUID
    var title: String
    var body: String
    let createdAt: Date
}

struct ScratchpadRevisionPolicy: Sendable {
    let minimumInterval: TimeInterval
    let minimumCharacterDelta: Int

    init(minimumInterval: TimeInterval = 30, minimumCharacterDelta: Int = 80) {
        self.minimumInterval = minimumInterval
        self.minimumCharacterDelta = minimumCharacterDelta
    }

    func shouldCreateRevision(
        previous: ScratchpadRevision?,
        note: ScratchpadNote,
        now: Date
    ) -> Bool {
        let hasMeaningfulContent = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard hasMeaningfulContent else { return false }
        guard let previous else { return true }
        guard previous.title != note.title || previous.body != note.body else { return false }
        let characterDelta = abs(previous.title.count + previous.body.count - note.title.count - note.body.count)
        return now.timeIntervalSince(previous.createdAt) >= minimumInterval
            || characterDelta >= minimumCharacterDelta
    }
}

enum CleanupIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal
    case balanced
    case polished

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AudioRetentionPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case disabled
    case oneDay
    case sevenDays
    case thirtyDays
    case untilDeleted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: "Off"
        case .oneDay: "1 day"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .untilDeleted: "Until deleted"
        }
    }

    var isEnabled: Bool { self != .disabled }

    func expirationDate(createdAt: Date) -> Date? {
        switch self {
        case .disabled: createdAt
        case .oneDay: createdAt.addingTimeInterval(86_400)
        case .sevenDays: createdAt.addingTimeInterval(7 * 86_400)
        case .thirtyDays: createdAt.addingTimeInterval(30 * 86_400)
        case .untilDeleted: nil
        }
    }
}

struct MurmurSettingsRecord: Identifiable, Codable, Equatable, Sendable {
    static let stableID = UUID(uuidString: "71F45FD6-B190-4AD1-8CC8-0D2F614064A3")!

    let id: UUID
    var removeSpeechArtifacts: Bool
    var whisperAwareCapture: Bool
    var cleanupIntensity: CleanupIntensity
    var showMenuBarItem: Bool
    var showLiveAudioMovement: Bool
    var allowFlowBarDocking: Bool
    var audioRetentionPolicy: AudioRetentionPolicy
    var errorNotifications: Bool
    var milestoneNotifications: Bool
    var commandModeEnabled: Bool
    var workspaceTaggingEnabled: Bool
    var preferredWhisperModelIdentifier: String
    var writing: WritingSettings

    static let `default` = MurmurSettingsRecord(
        id: stableID,
        removeSpeechArtifacts: true,
        whisperAwareCapture: true,
        cleanupIntensity: .balanced,
        showMenuBarItem: true,
        showLiveAudioMovement: true,
        allowFlowBarDocking: true,
        audioRetentionPolicy: .disabled,
        errorNotifications: true,
        milestoneNotifications: false,
        commandModeEnabled: true,
        workspaceTaggingEnabled: false,
        preferredWhisperModelIdentifier: "small.en",
        writing: .default
    )

    init(
        id: UUID,
        removeSpeechArtifacts: Bool,
        whisperAwareCapture: Bool,
        cleanupIntensity: CleanupIntensity,
        showMenuBarItem: Bool,
        showLiveAudioMovement: Bool,
        allowFlowBarDocking: Bool,
        audioRetentionPolicy: AudioRetentionPolicy,
        errorNotifications: Bool,
        milestoneNotifications: Bool,
        commandModeEnabled: Bool,
        workspaceTaggingEnabled: Bool,
        preferredWhisperModelIdentifier: String,
        writing: WritingSettings = .default
    ) {
        self.id = id
        self.removeSpeechArtifacts = removeSpeechArtifacts
        self.whisperAwareCapture = whisperAwareCapture
        self.cleanupIntensity = cleanupIntensity
        self.showMenuBarItem = showMenuBarItem
        self.showLiveAudioMovement = showLiveAudioMovement
        self.allowFlowBarDocking = allowFlowBarDocking
        self.audioRetentionPolicy = audioRetentionPolicy
        self.errorNotifications = errorNotifications
        self.milestoneNotifications = milestoneNotifications
        self.commandModeEnabled = commandModeEnabled
        self.workspaceTaggingEnabled = workspaceTaggingEnabled
        self.preferredWhisperModelIdentifier = preferredWhisperModelIdentifier
        self.writing = writing
    }

    var retainRawAudio: Bool {
        get { audioRetentionPolicy.isEnabled }
        set { audioRetentionPolicy = newValue ? .sevenDays : .disabled }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case removeSpeechArtifacts
        case whisperAwareCapture
        case cleanupIntensity
        case showMenuBarItem
        case showLiveAudioMovement
        case allowFlowBarDocking
        case retainRawAudio
        case audioRetentionPolicy
        case errorNotifications
        case milestoneNotifications
        case commandModeEnabled
        case workspaceTaggingEnabled
        case preferredWhisperModelIdentifier
        case writing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        removeSpeechArtifacts = try container.decode(Bool.self, forKey: .removeSpeechArtifacts)
        whisperAwareCapture = try container.decode(Bool.self, forKey: .whisperAwareCapture)
        cleanupIntensity = try container.decode(CleanupIntensity.self, forKey: .cleanupIntensity)
        showMenuBarItem = try container.decode(Bool.self, forKey: .showMenuBarItem)
        showLiveAudioMovement = try container.decode(Bool.self, forKey: .showLiveAudioMovement)
        allowFlowBarDocking = try container.decode(Bool.self, forKey: .allowFlowBarDocking)
        if let policy = try container.decodeIfPresent(
            AudioRetentionPolicy.self,
            forKey: .audioRetentionPolicy
        ) {
            audioRetentionPolicy = policy
        } else {
            let retained = try container.decodeIfPresent(Bool.self, forKey: .retainRawAudio) ?? false
            audioRetentionPolicy = retained ? .sevenDays : .disabled
        }
        errorNotifications = try container.decode(Bool.self, forKey: .errorNotifications)
        milestoneNotifications = try container.decode(Bool.self, forKey: .milestoneNotifications)
        commandModeEnabled = try container.decode(Bool.self, forKey: .commandModeEnabled)
        workspaceTaggingEnabled = try container.decode(Bool.self, forKey: .workspaceTaggingEnabled)
        preferredWhisperModelIdentifier = try container.decode(
            String.self,
            forKey: .preferredWhisperModelIdentifier
        )
        writing = try container.decodeIfPresent(WritingSettings.self, forKey: .writing) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(removeSpeechArtifacts, forKey: .removeSpeechArtifacts)
        try container.encode(whisperAwareCapture, forKey: .whisperAwareCapture)
        try container.encode(cleanupIntensity, forKey: .cleanupIntensity)
        try container.encode(showMenuBarItem, forKey: .showMenuBarItem)
        try container.encode(showLiveAudioMovement, forKey: .showLiveAudioMovement)
        try container.encode(allowFlowBarDocking, forKey: .allowFlowBarDocking)
        try container.encode(retainRawAudio, forKey: .retainRawAudio)
        try container.encode(audioRetentionPolicy, forKey: .audioRetentionPolicy)
        try container.encode(errorNotifications, forKey: .errorNotifications)
        try container.encode(milestoneNotifications, forKey: .milestoneNotifications)
        try container.encode(commandModeEnabled, forKey: .commandModeEnabled)
        try container.encode(workspaceTaggingEnabled, forKey: .workspaceTaggingEnabled)
        try container.encode(preferredWhisperModelIdentifier, forKey: .preferredWhisperModelIdentifier)
        try container.encode(writing, forKey: .writing)
    }
}

extension MurmurSettingsRecord {
    func applyingChange(_ mutate: (inout MurmurSettingsRecord) -> Void) -> MurmurSettingsRecord? {
        var candidate = self
        mutate(&candidate)
        return candidate == self ? nil : candidate
    }
}

struct DictationRuntimeConfiguration: Equatable, Sendable {
    var removeSpeechArtifacts: Bool
    var whisperAwareCapture: Bool
    var cleanupIntensity: CleanupIntensity
    var preferredWhisperModelIdentifier: String
    var audioRetentionPolicy: AudioRetentionPolicy
    var writing: WritingSettings
    var installedLocalWritingModelIdentifiers: Set<String>

    var retainRawAudio: Bool { audioRetentionPolicy.isEnabled }

    static let `default` = DictationRuntimeConfiguration(
        removeSpeechArtifacts: true,
        whisperAwareCapture: true,
        cleanupIntensity: .balanced,
        preferredWhisperModelIdentifier: "small.en",
        audioRetentionPolicy: .disabled,
        writing: .default,
        installedLocalWritingModelIdentifiers: []
    )

    init(settings: MurmurSettingsRecord, installedLocalWritingModelIdentifiers: Set<String> = []) {
        self.init(
            removeSpeechArtifacts: settings.removeSpeechArtifacts,
            whisperAwareCapture: settings.whisperAwareCapture,
            cleanupIntensity: settings.cleanupIntensity,
            preferredWhisperModelIdentifier: settings.preferredWhisperModelIdentifier,
            audioRetentionPolicy: settings.audioRetentionPolicy,
            writing: settings.writing,
            installedLocalWritingModelIdentifiers: installedLocalWritingModelIdentifiers
        )
    }

    init(
        removeSpeechArtifacts: Bool,
        whisperAwareCapture: Bool,
        cleanupIntensity: CleanupIntensity,
        preferredWhisperModelIdentifier: String,
        retainRawAudio: Bool = false,
        audioRetentionPolicy: AudioRetentionPolicy? = nil,
        writing: WritingSettings = .default,
        installedLocalWritingModelIdentifiers: Set<String>? = nil
    ) {
        self.removeSpeechArtifacts = removeSpeechArtifacts
        self.whisperAwareCapture = whisperAwareCapture
        self.cleanupIntensity = cleanupIntensity
        self.preferredWhisperModelIdentifier = preferredWhisperModelIdentifier
        self.audioRetentionPolicy = audioRetentionPolicy
            ?? (retainRawAudio ? .sevenDays : .disabled)
        self.writing = writing
        self.installedLocalWritingModelIdentifiers = installedLocalWritingModelIdentifiers
            ?? (writing.route == .localMLX ? [writing.localModelIdentifier] : [])
    }
}

enum SessionTransitionError: Error, Equatable, LocalizedError {
    case sessionAlreadyActive
    case noActiveSession
    case staleSession
    case invalidTransition(from: DictationPhase, to: DictationPhase)

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            "A dictation session is already active."
        case .noActiveSession:
            "There is no active dictation session."
        case .staleSession:
            "The result belongs to an older dictation session."
        case .invalidTransition(let from, let to):
            "Cannot move a dictation session from \(from.rawValue) to \(to.rawValue)."
        }
    }
}

struct DictationSessionStateMachine: Sendable {
    private(set) var session: DictationSession?

    mutating func start(
        id: UUID = UUID(),
        mode: DictationMode,
        targetBundleIdentifier: String?,
        now: Date = Date()
    ) throws -> UUID {
        if let session, session.phase.isTerminal == false {
            throw SessionTransitionError.sessionAlreadyActive
        }

        session = DictationSession(
            id: id,
            mode: mode,
            startedAt: now,
            endedAt: nil,
            targetBundleIdentifier: targetBundleIdentifier,
            provisionalText: "",
            finalText: "",
            phase: .calibrating
        )
        return id
    }

    mutating func beginListening(sessionID: UUID) throws {
        try transition(sessionID: sessionID, from: [.calibrating], to: .listening)
    }

    mutating func promoteToCommand(sessionID: UUID) throws {
        guard var session else { throw SessionTransitionError.noActiveSession }
        guard session.id == sessionID else { throw SessionTransitionError.staleSession }
        guard session.phase == .calibrating || session.phase == .listening else {
            throw SessionTransitionError.invalidTransition(from: session.phase, to: session.phase)
        }
        session.mode = .command
        self.session = session
    }

    mutating func updateProvisional(_ text: String, sessionID: UUID) throws {
        guard var session else { throw SessionTransitionError.noActiveSession }
        guard session.id == sessionID else { throw SessionTransitionError.staleSession }
        guard session.phase == .listening else {
            throw SessionTransitionError.invalidTransition(from: session.phase, to: .listening)
        }
        session.provisionalText = text
        self.session = session
    }

    mutating func beginFinalizing(sessionID: UUID) throws {
        try transition(sessionID: sessionID, from: [.listening], to: .finalizing)
    }

    mutating func beginInserting(finalText: String, sessionID: UUID) throws {
        guard var session else { throw SessionTransitionError.noActiveSession }
        guard session.id == sessionID else { throw SessionTransitionError.staleSession }
        guard session.phase == .finalizing else {
            throw SessionTransitionError.invalidTransition(from: session.phase, to: .inserting)
        }
        session.finalText = finalText
        session.phase = .inserting
        self.session = session
    }

    mutating func complete(sessionID: UUID, now: Date = Date()) throws {
        try finish(sessionID: sessionID, phase: .completed, now: now)
    }

    mutating func fail(sessionID: UUID, now: Date = Date()) throws {
        guard let session else { throw SessionTransitionError.noActiveSession }
        guard session.id == sessionID else { throw SessionTransitionError.staleSession }
        guard session.phase.isTerminal == false else {
            throw SessionTransitionError.invalidTransition(from: session.phase, to: .failed)
        }
        try finish(sessionID: sessionID, phase: .failed, now: now)
    }

    mutating func cancel(sessionID: UUID, now: Date = Date()) throws {
        guard let session else { throw SessionTransitionError.noActiveSession }
        guard session.id == sessionID else { throw SessionTransitionError.staleSession }
        guard session.phase.isTerminal == false else {
            throw SessionTransitionError.invalidTransition(from: session.phase, to: .cancelled)
        }
        try finish(sessionID: sessionID, phase: .cancelled, now: now)
    }

    private mutating func transition(
        sessionID: UUID,
        from allowedPhases: Set<DictationPhase>,
        to phase: DictationPhase
    ) throws {
        guard var session else { throw SessionTransitionError.noActiveSession }
        guard session.id == sessionID else { throw SessionTransitionError.staleSession }
        guard allowedPhases.contains(session.phase) else {
            throw SessionTransitionError.invalidTransition(from: session.phase, to: phase)
        }
        session.phase = phase
        self.session = session
    }

    private mutating func finish(sessionID: UUID, phase: DictationPhase, now: Date) throws {
        guard var session else { throw SessionTransitionError.noActiveSession }
        guard session.id == sessionID else { throw SessionTransitionError.staleSession }
        guard session.phase == .inserting || phase != .completed else {
            throw SessionTransitionError.invalidTransition(from: session.phase, to: phase)
        }
        guard session.phase.isTerminal == false else {
            throw SessionTransitionError.invalidTransition(from: session.phase, to: phase)
        }
        session.phase = phase
        session.endedAt = now
        self.session = session
    }
}

private extension DictationPhase {
    var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}
