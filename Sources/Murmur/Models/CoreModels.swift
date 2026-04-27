import Foundation

enum DictationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case pushToTalk
    case handsFree
    case command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pushToTalk:
            "Push To Talk"
        case .handsFree:
            "Hands Free"
        case .command:
            "Command"
        }
    }
}

enum CleanupLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case light
    case medium
    case heavy

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum AppWritingContext: String, Codable, CaseIterable, Identifiable, Sendable {
    case chat
    case email
    case document
    case code
    case terminal
    case browserForm
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browserForm:
            "Browser Form"
        default:
            rawValue.capitalized
        }
    }
}

enum SessionPhase: String, Codable, Sendable {
    case idle
    case listening
    case processing
    case completed
    case failed
}

struct AudioMetrics: Codable, Equatable, Sendable {
    var averagePower: Double
    var peakPower: Double
    var sampleCount: Int
    var duration: TimeInterval

    static let zero = AudioMetrics(averagePower: 0, peakPower: 0, sampleCount: 0, duration: 0)
}

struct HotkeyShortcut: Codable, Equatable, Sendable {
    var displayName: String
    var detail: String

    static let pushToTalk = HotkeyShortcut(displayName: "Control + Option", detail: "Hold to dictate")
    static let handsFree = HotkeyShortcut(displayName: "Control + Option + Space", detail: "Toggle hands-free mode")
    static let command = HotkeyShortcut(displayName: "Control + Option + Command", detail: "Hold to transform selected text")
}

struct DictationSession: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var mode: DictationMode
    var appContext: AppWritingContext
    var sourceAppBundleID: String
    var localeIdentifier: String
    var startedAt: Date
    var endedAt: Date?
    var audioMetrics: AudioMetrics
    var partialTranscript: String
    var finalTranscript: String
    var insertionOutcome: InsertionOutcome
    var commandApplied: String?
}

struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var sourceAppName: String
    var sourceAppBundleID: String
    var appContext: AppWritingContext
    var mode: DictationMode
    var cleanupLevel: CleanupLevel
    var finalText: String
    var commandApplied: String?
    var recoveryMetadata: String?
    var audioReference: String?
    var insertionOutcome: InsertionOutcome
}

struct Snippet: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var trigger: String
    var expansion: String
}

struct DictionaryEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var phrase: String
    var replacement: String
    var context: AppWritingContext?
}

struct StyleProfile: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var context: AppWritingContext
    var name: String
    var instructions: String
}

struct VoiceCommandTemplate: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var trigger: String
    var instructions: String
}

struct ModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    enum Runtime: String, Codable, CaseIterable, Sendable {
        case appleSpeech
        case foundationModels
        case whisperCPP
        case llamaCPP
    }

    enum Status: String, Codable, CaseIterable, Sendable {
        case ready
        case needsDownload
        case installing
        case imported
        case unavailable
    }

    var id: UUID
    var name: String
    var runtime: Runtime
    var modelIdentifier: String?
    var localeIdentifier: String?
    var status: Status
    var storagePath: String?
    var notes: String
}

struct RuntimeInstallation: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case whisperCPP = "whisper.cpp"
        case llamaCPP = "llama.cpp"
    }

    enum InstallState: String, Codable, CaseIterable, Sendable {
        case notInstalled
        case installing
        case installed
        case failed
    }

    enum DetectionSource: String, Codable, CaseIterable, Sendable {
        case bundled
        case path
        case managed
        case unknown
    }

    var id: UUID
    var kind: Kind
    var installState: InstallState
    var installPath: String?
    var version: String?
    var notes: String
    var lastUpdatedAt: Date?
    var detectionSource: DetectionSource
}

struct TaskProgressState: Equatable, Sendable {
    var title: String
    var detail: String
    var fractionCompleted: Double?
}

enum WhisperModelPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case tiny = "tiny"
    case tinyEn = "tiny.en"
    case base = "base"
    case baseEn = "base.en"
    case small = "small"
    case smallEn = "small.en"
    case medium = "medium"
    case mediumEn = "medium.en"
    case largeV3 = "large-v3"
    case largeV3Turbo = "large-v3-turbo"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var downloadArgument: String { rawValue }

    var fileName: String { "ggml-\(rawValue).bin" }

    var sizeLabel: String {
        switch self {
        case .tiny, .tinyEn:
            "75 MiB"
        case .base, .baseEn:
            "142 MiB"
        case .small, .smallEn:
            "466 MiB"
        case .medium, .mediumEn:
            "1.5 GiB"
        case .largeV3:
            "2.9 GiB"
        case .largeV3Turbo:
            "1.5 GiB"
        }
    }

    var summary: String {
        switch self {
        case .tiny, .tinyEn:
            "Fastest, lowest accuracy. Useful for lightweight dictation."
        case .base, .baseEn:
            "Balanced speed for general dictation on smaller systems."
        case .small, .smallEn:
            "Good default for local dictation with better accuracy."
        case .medium, .mediumEn:
            "Higher accuracy with significantly more memory usage."
        case .largeV3:
            "Highest accuracy, best for multilingual transcription."
        case .largeV3Turbo:
            "Large-v3-turbo balance: strong accuracy with lower footprint."
        }
    }

    var localeIdentifier: String? {
        rawValue.contains(".en") ? "en_US" : nil
    }

    static var recommended: WhisperModelPreset { .smallEn }

    static func catalogDescriptors() -> [ModelDescriptor] {
        allCases.map { preset in
            ModelDescriptor(
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
    }
}

enum LlamaModelPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case gemma3_1b_it_q4km = "gemma-3-1b-it-Q4_K_M"
    case gemma3_270m_it_q8 = "gemma-3-270m-it-Q8_0"
    case qwen25Coder_05b_q8 = "qwen2.5-coder-0.5b-q8_0"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemma3_1b_it_q4km:
            "Gemma 3 1B Instruct Q4_K_M"
        case .gemma3_270m_it_q8:
            "Gemma 3 270M Instruct Q8_0"
        case .qwen25Coder_05b_q8:
            "Qwen2.5 Coder 0.5B Q8_0"
        }
    }

    var repoIdentifier: String {
        switch self {
        case .gemma3_1b_it_q4km:
            "ggml-org/gemma-3-1b-it-GGUF"
        case .gemma3_270m_it_q8:
            "ggml-org/gemma-3-270m-it-GGUF"
        case .qwen25Coder_05b_q8:
            "ggml-org/Qwen2.5-Coder-0.5B-Q8_0-GGUF"
        }
    }

    var fileName: String {
        switch self {
        case .gemma3_1b_it_q4km:
            "gemma-3-1b-it-Q4_K_M.gguf"
        case .gemma3_270m_it_q8:
            "gemma-3-270m-it-Q8_0.gguf"
        case .qwen25Coder_05b_q8:
            "qwen2.5-coder-0.5b-q8_0.gguf"
        }
    }

    var sizeLabel: String {
        switch self {
        case .gemma3_1b_it_q4km:
            "806 MiB"
        case .gemma3_270m_it_q8:
            "292 MiB"
        case .qwen25Coder_05b_q8:
            "531 MiB"
        }
    }

    var summary: String {
        switch self {
        case .gemma3_1b_it_q4km:
            "Recommended default for rewrite, summarize, and translate with better quality than tiny local models."
        case .gemma3_270m_it_q8:
            "Lightweight fallback for smaller systems or faster low-cost local edits."
        case .qwen25Coder_05b_q8:
            "Small coder-oriented model that is useful when command mode is used against code or terminal text."
        }
    }

    static var recommended: LlamaModelPreset { .gemma3_1b_it_q4km }

    static func catalogDescriptors() -> [ModelDescriptor] {
        allCases.map { preset in
            ModelDescriptor(
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
}

struct NoteDocument: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
}

struct UsageStats: Codable, Equatable, Sendable {
    var totalWords: Int
    var averageWordsPerMinute: Double
    var totalSessions: Int
    var lastSessionAt: Date?

    static let empty = UsageStats(totalWords: 0, averageWordsPerMinute: 0, totalSessions: 0, lastSessionAt: nil)
}

struct AppPermissions: Codable, Equatable, Sendable {
    var microphoneGranted: Bool
    var speechRecognitionGranted: Bool
    var accessibilityGranted: Bool

    static let unknown = AppPermissions(
        microphoneGranted: false,
        speechRecognitionGranted: false,
        accessibilityGranted: false
    )
}

struct InsertionOutcome: Codable, Equatable, Sendable {
    enum Method: String, Codable, Sendable {
        case accessibility
        case clipboard
        case none
    }

    var succeeded: Bool
    var method: Method
    var message: String

    static let pending = InsertionOutcome(succeeded: false, method: .none, message: "Pending")
    static let unavailable = InsertionOutcome(succeeded: false, method: .none, message: "Unavailable")
}

struct DiagnosticsSnapshot: Codable, Sendable {
    var exportedAt: Date
    var redacted: Bool
    var permissions: AppPermissions
    var activeMode: DictationMode?
    var cleanupLevel: CleanupLevel
    var localeIdentifier: String
    var historyCount: Int
    var noteCount: Int
    var runtimes: [RuntimeInstallation]
    var modelStatuses: [ModelDescriptor]
    var latestHistory: [HistoryEntry]
}

struct FrontmostAppDescriptor: Equatable, Sendable {
    var localizedName: String
    var bundleIdentifier: String
    var writingContext: AppWritingContext
}

enum SidebarDestination: String, CaseIterable, Identifiable {
    case dashboard
    case history
    case snippets
    case dictionary
    case styles
    case notes
    case models
    case settings

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

struct PersonalizationSnapshot: Codable, Equatable, Sendable {
    var snippets: [Snippet]
    var dictionaryEntries: [DictionaryEntry]
    var styleProfiles: [StyleProfile]
    var commandTemplates: [VoiceCommandTemplate]

    static let `default` = PersonalizationSnapshot(
        snippets: [
            Snippet(id: UUID(), trigger: "my schedule link", expansion: "https://cal.com/murmur/demo")
        ],
        dictionaryEntries: [
            DictionaryEntry(id: UUID(), phrase: "Murmur", replacement: "Murmur", context: nil),
            DictionaryEntry(id: UUID(), phrase: "Wispr", replacement: "Wispr", context: nil),
            DictionaryEntry(id: UUID(), phrase: "snake case", replacement: "snake_case", context: .code)
        ],
        styleProfiles: [
            StyleProfile(id: UUID(), context: .chat, name: "Conversational", instructions: "Keep the tone concise and conversational."),
            StyleProfile(id: UUID(), context: .email, name: "Professional", instructions: "Make the text clear, professional, and direct."),
            StyleProfile(id: UUID(), context: .document, name: "Polished", instructions: "Improve grammar and clarity while preserving meaning."),
            StyleProfile(id: UUID(), context: .code, name: "Code-safe", instructions: "Preserve syntax, symbols, and identifier casing.")
        ],
        commandTemplates: [
            VoiceCommandTemplate(id: UUID(), name: "Summarize", trigger: "summarize this", instructions: "Summarize the selected text in three sentences."),
            VoiceCommandTemplate(id: UUID(), name: "Concise", trigger: "make this concise", instructions: "Rewrite the selected text to be more concise while preserving the meaning."),
            VoiceCommandTemplate(id: UUID(), name: "Translate", trigger: "translate to spanish", instructions: "Translate the selected text to Spanish.")
        ]
    )
}

struct SettingsSnapshot: Codable, Equatable, Sendable {
    var cleanupLevel: CleanupLevel
    var localeIdentifier: String
    var retainAudioHistory: Bool
    var preferredWhisperModelIdentifier: String
    var preferredLlamaModelIdentifier: String
    var pushToTalkShortcut: HotkeyShortcut
    var handsFreeShortcut: HotkeyShortcut
    var commandShortcut: HotkeyShortcut

    static let `default` = SettingsSnapshot(
        cleanupLevel: .light,
        localeIdentifier: Locale.autoupdatingCurrent.identifier,
        retainAudioHistory: false,
        preferredWhisperModelIdentifier: WhisperModelPreset.recommended.rawValue,
        preferredLlamaModelIdentifier: LlamaModelPreset.recommended.rawValue,
        pushToTalkShortcut: .pushToTalk,
        handsFreeShortcut: .handsFree,
        commandShortcut: .command
    )
}

struct RuntimeInventorySnapshot: Codable, Equatable, Sendable {
    var runtimes: [RuntimeInstallation]
    var models: [ModelDescriptor]

    static let `default` = RuntimeInventorySnapshot(
        runtimes: [
            RuntimeInstallation(
                id: UUID(),
                kind: .whisperCPP,
                installState: .notInstalled,
                installPath: nil,
                version: nil,
                notes: "Clone and build the official whisper.cpp runtime for local transcription adapters.",
                lastUpdatedAt: nil,
                detectionSource: .unknown
            ),
            RuntimeInstallation(
                id: UUID(),
                kind: .llamaCPP,
                installState: .notInstalled,
                installPath: nil,
                version: nil,
                notes: "Clone and build the official llama.cpp runtime for local rewrite and command adapters.",
                lastUpdatedAt: nil,
                detectionSource: .unknown
            )
        ],
        models: WhisperModelPreset.catalogDescriptors() + LlamaModelPreset.catalogDescriptors()
    )
}
