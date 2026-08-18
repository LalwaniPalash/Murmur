import CryptoKit
import Foundation

public struct AudioCorpusManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var fixtures: [AudioCorpusFixture]

    public init(version: Int, fixtures: [AudioCorpusFixture]) {
        self.version = version
        self.fixtures = fixtures
    }
}

public struct AudioCorpusFixture: Codable, Equatable, Sendable {
    public var id: String
    public var source: CorpusFixtureSource
    public var expectedTranscript: String
    public var requiredPhrases: [RequiredPhrase]
    public var protectedTokens: [String]
    public var language: String
    public var speechCondition: SpeechCondition
    public var microphoneClass: MicrophoneClass
    public var tags: [String]
    public var consent: CorpusConsent
    public var expectedSHA256: String?

    public init(
        id: String,
        source: CorpusFixtureSource,
        expectedTranscript: String,
        requiredPhrases: [RequiredPhrase],
        protectedTokens: [String],
        language: String,
        speechCondition: SpeechCondition,
        microphoneClass: MicrophoneClass,
        tags: [String],
        consent: CorpusConsent,
        expectedSHA256: String? = nil
    ) {
        self.id = id
        self.source = source
        self.expectedTranscript = expectedTranscript
        self.requiredPhrases = requiredPhrases
        self.protectedTokens = protectedTokens
        self.language = language
        self.speechCondition = speechCondition
        self.microphoneClass = microphoneClass
        self.tags = tags
        self.consent = consent
        self.expectedSHA256 = expectedSHA256
    }
}

public enum CorpusFixtureSource: Equatable, Sendable {
    case audioFile(path: String)
    case synthesis(text: String, voice: String, rate: Int)

    public var synthesisText: String? {
        guard case .synthesis(let text, _, _) = self else { return nil }
        return text
    }

    public var audioPath: String? {
        guard case .audioFile(let path) = self else { return nil }
        return path
    }
}

extension CorpusFixtureSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case text
        case voice
        case rate
    }

    private enum Kind: String, Codable {
        case audioFile
        case synthesis
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .audioFile:
            self = .audioFile(path: try container.decode(String.self, forKey: .path))
        case .synthesis:
            self = .synthesis(
                text: try container.decode(String.self, forKey: .text),
                voice: try container.decodeIfPresent(String.self, forKey: .voice) ?? "Samantha",
                rate: try container.decodeIfPresent(Int.self, forKey: .rate) ?? 180
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .audioFile(let path):
            try container.encode(Kind.audioFile, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .synthesis(let text, let voice, let rate):
            try container.encode(Kind.synthesis, forKey: .kind)
            try container.encode(text, forKey: .text)
            try container.encode(voice, forKey: .voice)
            try container.encode(rate, forKey: .rate)
        }
    }
}

public struct CorpusConsent: Codable, Equatable, Sendable {
    public var origin: CorpusOrigin
    public var license: String
    public var permissionReference: String?

    public init(origin: CorpusOrigin, license: String, permissionReference: String? = nil) {
        self.origin = origin
        self.license = license
        self.permissionReference = permissionReference
    }
}

public enum CorpusOrigin: String, Codable, Equatable, Sendable {
    case synthetic
    case recorded
}

public enum SpeechCondition: String, Codable, CaseIterable, Equatable, Sendable {
    case normal
    case quiet
    case whisper
    case noisy
    case distant
}

public enum MicrophoneClass: String, Codable, CaseIterable, Equatable, Sendable {
    case builtIn
    case bluetooth
    case external
    case synthetic
    case unknown
}

public struct RequiredPhrase: Codable, Equatable, Hashable, Sendable {
    public var text: String
    public var region: TranscriptRegion

    public init(text: String, region: TranscriptRegion) {
        self.text = text
        self.region = region
    }
}

public enum TranscriptRegion: String, Codable, Equatable, Hashable, Sendable {
    case beginning
    case middle
    case end
    case anywhere
}

public enum CorpusManifestLoader {
    public static func decode(_ data: Data) throws -> AudioCorpusManifest {
        let decoder = JSONDecoder()
        return try decoder.decode(AudioCorpusManifest.self, from: data)
    }

    public static func load(from url: URL) throws -> AudioCorpusManifest {
        try decode(Data(contentsOf: url, options: [.mappedIfSafe]))
    }
}

public struct CorpusManifestValidationIssue: Codable, Equatable, Sendable {
    public var fixtureID: String?
    public var code: CorpusManifestValidationCode
    public var message: String

    public init(fixtureID: String?, code: CorpusManifestValidationCode, message: String) {
        self.fixtureID = fixtureID
        self.code = code
        self.message = message
    }
}

public enum CorpusManifestValidationCode: String, Codable, Equatable, Sendable {
    case unsupportedVersion
    case emptyCorpus
    case invalidFixtureID
    case duplicateFixtureID
    case emptyExpectedTranscript
    case invalidLanguage
    case missingLicense
    case missingPermissionReference
    case unsafePath
    case unsupportedAudioFormat
    case missingAudioFile
    case invalidDigest
    case digestMismatch
    case invalidSynthesis
    case invalidRequiredPhrase
    case invalidProtectedToken
}

public struct CorpusManifestValidationError: Error, Equatable, Sendable {
    public let issues: [CorpusManifestValidationIssue]

    public init(issues: [CorpusManifestValidationIssue]) {
        self.issues = issues
    }
}

extension CorpusManifestValidationError: LocalizedError {
    public var errorDescription: String? {
        issues.map { issue in
            [issue.fixtureID, issue.code.rawValue, issue.message]
                .compactMap { $0 }
                .joined(separator: ": ")
        }.joined(separator: "\n")
    }
}

public enum CorpusManifestValidator {
    private static let supportedAudioExtensions: Set<String> = ["wav", "wave", "aiff", "aif", "m4a", "mp3"]
    private static let fixtureIDPattern = try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9._-]{0,127}$")
    private static let languagePattern = try! NSRegularExpression(
        pattern: "^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$"
    )
    private static let digestPattern = try! NSRegularExpression(pattern: "^[a-fA-F0-9]{64}$")

    public static func validate(
        _ manifest: AudioCorpusManifest,
        baseDirectory: URL
    ) throws -> AudioCorpusManifest {
        var issues: [CorpusManifestValidationIssue] = []
        if manifest.version != 1 {
            issues.append(.init(
                fixtureID: nil,
                code: .unsupportedVersion,
                message: "Only corpus version 1 is supported."
            ))
        }
        if manifest.fixtures.isEmpty {
            issues.append(.init(fixtureID: nil, code: .emptyCorpus, message: "The corpus has no fixtures."))
        }
        if manifest.fixtures.count > 10_000 {
            issues.append(.init(fixtureID: nil, code: .emptyCorpus, message: "The corpus exceeds 10,000 fixtures."))
        }

        let base = baseDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var seenIDs: Set<String> = []
        for fixture in manifest.fixtures {
            let fixtureID = fixture.id
            if !matches(fixtureIDPattern, fixtureID) {
                issues.append(.init(
                    fixtureID: fixtureID,
                    code: .invalidFixtureID,
                    message: "Fixture IDs must be lowercase and path-safe."
                ))
            }
            if !seenIDs.insert(fixtureID).inserted {
                issues.append(.init(
                    fixtureID: fixtureID,
                    code: .duplicateFixtureID,
                    message: "Fixture IDs must be unique."
                ))
            }
            if fixture.expectedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(
                    fixtureID: fixtureID,
                    code: .emptyExpectedTranscript,
                    message: "Expected transcript cannot be empty."
                ))
            }
            if !matches(languagePattern, fixture.language) {
                issues.append(.init(
                    fixtureID: fixtureID,
                    code: .invalidLanguage,
                    message: "Language must be a BCP-47 style identifier."
                ))
            }
            if fixture.consent.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(
                    fixtureID: fixtureID,
                    code: .missingLicense,
                    message: "Every fixture requires license metadata."
                ))
            }
            if fixture.consent.origin == .recorded,
               fixture.consent.permissionReference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(.init(
                    fixtureID: fixtureID,
                    code: .missingPermissionReference,
                    message: "Recorded speech requires a permission reference."
                ))
            }
            for phrase in fixture.requiredPhrases where phrase.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(
                    fixtureID: fixtureID,
                    code: .invalidRequiredPhrase,
                    message: "Required phrases cannot be empty."
                ))
            }
            for token in fixture.protectedTokens where token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(
                    fixtureID: fixtureID,
                    code: .invalidProtectedToken,
                    message: "Protected tokens cannot be empty."
                ))
            }

            switch fixture.source {
            case .synthesis(let text, let voice, let rate):
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !(80...500).contains(rate)
                {
                    issues.append(.init(
                        fixtureID: fixtureID,
                        code: .invalidSynthesis,
                        message: "Synthesis requires text, voice, and a rate from 80 through 500."
                    ))
                }
            case .audioFile(let path):
                validateAudioPath(
                    path,
                    expectedSHA256: fixture.expectedSHA256,
                    fixtureID: fixtureID,
                    baseDirectory: base,
                    issues: &issues
                )
            }
        }

        if !issues.isEmpty {
            throw CorpusManifestValidationError(issues: issues)
        }
        return manifest
    }

    private static func validateAudioPath(
        _ path: String,
        expectedSHA256: String?,
        fixtureID: String,
        baseDirectory: URL,
        issues: inout [CorpusManifestValidationIssue]
    ) {
        let pathComponents = NSString(string: path).pathComponents
        let unsafe = NSString(string: path).isAbsolutePath
            || pathComponents.contains("..")
            || path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !unsafe else {
            issues.append(.init(
                fixtureID: fixtureID,
                code: .unsafePath,
                message: "Audio paths must remain inside the corpus directory."
            ))
            return
        }

        let url = baseDirectory.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        let basePath = baseDirectory.path.hasSuffix("/") ? baseDirectory.path : baseDirectory.path + "/"
        guard url.path.hasPrefix(basePath) else {
            issues.append(.init(
                fixtureID: fixtureID,
                code: .unsafePath,
                message: "Audio paths must remain inside the corpus directory."
            ))
            return
        }

        if !supportedAudioExtensions.contains(url.pathExtension.lowercased()) {
            issues.append(.init(
                fixtureID: fixtureID,
                code: .unsupportedAudioFormat,
                message: "Unsupported audio extension: \(url.pathExtension)."
            ))
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            issues.append(.init(
                fixtureID: fixtureID,
                code: .missingAudioFile,
                message: "Audio file does not exist."
            ))
            return
        }
        if let expectedSHA256 {
            guard matches(digestPattern, expectedSHA256) else {
                issues.append(.init(
                    fixtureID: fixtureID,
                    code: .invalidDigest,
                    message: "Expected SHA-256 must contain 64 hexadecimal characters."
                ))
                return
            }
            do {
                if try CorpusFixtureDigest.sha256(of: url)
                    .caseInsensitiveCompare(expectedSHA256) != .orderedSame
                {
                    issues.append(.init(
                        fixtureID: fixtureID,
                        code: .digestMismatch,
                        message: "Audio digest does not match the manifest."
                    ))
                }
            } catch {
                issues.append(.init(
                    fixtureID: fixtureID,
                    code: .digestMismatch,
                    message: "Audio digest could not be computed."
                ))
            }
        }
    }

    private static func matches(_ expression: NSRegularExpression, _ value: String) -> Bool {
        expression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        ) != nil
    }
}

public enum CorpusFixtureDigest {
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
