import Foundation

enum HubDestination: String, CaseIterable, Identifiable, Sendable {
    case home
    case dictionary
    case snippets
    case style
    case scratchpad
    case models
    case settings
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .dictionary: "Dictionary"
        case .snippets: "Snippets"
        case .style: "Style"
        case .scratchpad: "Scratchpad"
        case .models: "Models"
        case .settings: "Settings"
        case .help: "Help"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .style: "wand.and.stars"
        case .scratchpad: "square.and.pencil"
        case .models: "cpu"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
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
    let mode: DictationMode
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

struct MurmurSettingsRecord: Identifiable, Codable, Equatable, Sendable {
    static let stableID = UUID(uuidString: "71F45FD6-B190-4AD1-8CC8-0D2F614064A3")!

    let id: UUID
    var removeSpeechArtifacts: Bool
    var whisperAwareCapture: Bool
    var cleanupIntensity: CleanupIntensity
    var showMenuBarItem: Bool
    var showLiveAudioMovement: Bool
    var allowFlowBarDocking: Bool
    var retainRawAudio: Bool
    var errorNotifications: Bool
    var milestoneNotifications: Bool
    var commandModeEnabled: Bool
    var workspaceTaggingEnabled: Bool
    var preferredWhisperModelIdentifier: String

    static let `default` = MurmurSettingsRecord(
        id: stableID,
        removeSpeechArtifacts: true,
        whisperAwareCapture: true,
        cleanupIntensity: .balanced,
        showMenuBarItem: true,
        showLiveAudioMovement: true,
        allowFlowBarDocking: true,
        retainRawAudio: false,
        errorNotifications: true,
        milestoneNotifications: false,
        commandModeEnabled: true,
        workspaceTaggingEnabled: false,
        preferredWhisperModelIdentifier: "small.en"
    )
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
    var retainRawAudio: Bool

    static let `default` = DictationRuntimeConfiguration(
        removeSpeechArtifacts: true,
        whisperAwareCapture: true,
        cleanupIntensity: .balanced,
        preferredWhisperModelIdentifier: "small.en",
        retainRawAudio: false
    )

    init(settings: MurmurSettingsRecord) {
        self.init(
            removeSpeechArtifacts: settings.removeSpeechArtifacts,
            whisperAwareCapture: settings.whisperAwareCapture,
            cleanupIntensity: settings.cleanupIntensity,
            preferredWhisperModelIdentifier: settings.preferredWhisperModelIdentifier,
            retainRawAudio: settings.retainRawAudio
        )
    }

    init(
        removeSpeechArtifacts: Bool,
        whisperAwareCapture: Bool,
        cleanupIntensity: CleanupIntensity,
        preferredWhisperModelIdentifier: String,
        retainRawAudio: Bool = false
    ) {
        self.removeSpeechArtifacts = removeSpeechArtifacts
        self.whisperAwareCapture = whisperAwareCapture
        self.cleanupIntensity = cleanupIntensity
        self.preferredWhisperModelIdentifier = preferredWhisperModelIdentifier
        self.retainRawAudio = retainRawAudio
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
