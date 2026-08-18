import Foundation

enum IssueBundleError: Error, Equatable, LocalizedError {
    case invalidMetadata
    case transcriptTooLarge
    case audioTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidMetadata: "The issue metadata is invalid."
        case .transcriptTooLarge: "The selected transcript is too large to export safely."
        case .audioTooLarge: "The selected recording is too large to export safely."
        }
    }
}

struct IssueBundleOptions: Equatable, Sendable {
    var includeTranscript = false
    var includeAudio = false
}

struct IssueBundleRequest: Equatable, Sendable {
    let session: SourceSessionRecord
    let result: TranscriptResultVersion
    let failureCode: String?
    let modelSHA256: String?
}

struct IssueBundlePreviewField: Identifiable, Equatable, Sendable {
    var id: String { path }
    let path: String
    let isPrivate: Bool
    let isIncluded: Bool
}

struct IssueBundlePreview: Equatable, Sendable {
    let fields: [IssueBundlePreviewField]

    var includedFields: [IssueBundlePreviewField] { fields.filter(\.isIncluded) }
    var includesPrivateContent: Bool { includedFields.contains(where: \.isPrivate) }
}

struct IssueBundleDocument: Codable, Equatable, Sendable {
    struct Environment: Codable, Equatable, Sendable {
        let appVersion: String
        let operatingSystem: String
        let architecture: String
    }

    struct Consent: Codable, Equatable, Sendable {
        let transcriptIncluded: Bool
        let audioIncluded: Bool
    }

    struct Session: Codable, Equatable, Sendable {
        let id: UUID
        let recordingDuration: TimeInterval
        let processingDuration: TimeInterval
        let insertionSucceeded: Bool
        let failureCode: String?
    }

    struct Runtime: Codable, Equatable, Sendable {
        let providerIdentifier: String
        let modelIdentifier: String
        let modelSHA256: String?
        let language: String
    }

    struct Transcript: Codable, Equatable, Sendable {
        let raw: String
        let final: String
    }

    struct Audio: Codable, Equatable, Sendable {
        let format: String
        let sampleRate: Int
        let sampleCount: Int
        let waveData: Data
    }

    let format: String
    let version: Int
    let exportedAt: Date
    let environment: Environment
    let consent: Consent
    let session: Session
    let runtime: Runtime
    let transcript: Transcript?
    let audio: Audio?
}

actor IssueBundleService {
    private static let maximumTranscriptBytes = 1_000_000
    private static let maximumAudioBytes = 128 * 1_024 * 1_024

    private let retention: RetentionCoordinator
    private let appVersion: String
    private let operatingSystem: String
    private let architecture: String

    init(
        retention: RetentionCoordinator,
        appVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development",
        operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: String = IssueBundleService.currentArchitecture
    ) {
        self.retention = retention
        self.appVersion = appVersion
        self.operatingSystem = operatingSystem
        self.architecture = architecture
    }

    func preview(
        request: IssueBundleRequest,
        options: IssueBundleOptions
    ) throws -> IssueBundlePreview {
        try validate(request: request, options: options)
        let alwaysIncluded = [
            "format", "version", "exportedAt", "environment.appVersion",
            "environment.operatingSystem", "environment.architecture",
            "consent.transcriptIncluded", "consent.audioIncluded", "session.id",
            "session.recordingDuration", "session.processingDuration",
            "session.insertionSucceeded", "runtime.providerIdentifier",
            "runtime.modelIdentifier", "runtime.language",
        ]
        var fields = alwaysIncluded.map {
            IssueBundlePreviewField(path: $0, isPrivate: false, isIncluded: true)
        }
        fields.append(IssueBundlePreviewField(
            path: "session.failureCode",
            isPrivate: false,
            isIncluded: request.failureCode != nil
        ))
        fields.append(IssueBundlePreviewField(
            path: "runtime.modelSHA256",
            isPrivate: false,
            isIncluded: request.modelSHA256 != nil
        ))
        fields += [
            IssueBundlePreviewField(
                path: "transcript.raw",
                isPrivate: true,
                isIncluded: options.includeTranscript
            ),
            IssueBundlePreviewField(
                path: "transcript.final",
                isPrivate: true,
                isIncluded: options.includeTranscript
            ),
            IssueBundlePreviewField(
                path: "audio.waveData",
                isPrivate: true,
                isIncluded: options.includeAudio
            ),
        ]
        return IssueBundlePreview(fields: fields)
    }

    func makeBundle(
        request: IssueBundleRequest,
        options: IssueBundleOptions,
        exportedAt: Date = Date()
    ) async throws -> Data {
        try validate(request: request, options: options)
        let audio: IssueBundleDocument.Audio?
        if options.includeAudio {
            guard let metadata = try await retention.retainedRecord(sessionID: request.session.id),
                  metadata.sampleCount <= (Self.maximumAudioBytes - 44) / 2,
                  let sampleRate = UInt32(exactly: metadata.sampleRate),
                  (8_000...384_000).contains(sampleRate)
            else { throw IssueBundleError.audioTooLarge }
            let retained = try await retention.samples(sessionID: request.session.id)
            let waveData = try WaveFileEncoder.encode(
                samples: retained.samples,
                sampleRate: sampleRate
            )
            guard waveData.count <= Self.maximumAudioBytes else {
                throw IssueBundleError.audioTooLarge
            }
            audio = IssueBundleDocument.Audio(
                format: "wav-pcm16-mono",
                sampleRate: retained.sampleRate,
                sampleCount: retained.samples.count,
                waveData: waveData
            )
        } else {
            audio = nil
        }
        let transcript = options.includeTranscript
            ? IssueBundleDocument.Transcript(
                raw: request.result.rawTranscript,
                final: request.result.finalTranscript
            )
            : nil
        let document = IssueBundleDocument(
            format: "murmur-issue",
            version: 1,
            exportedAt: exportedAt,
            environment: .init(
                appVersion: appVersion,
                operatingSystem: operatingSystem,
                architecture: architecture
            ),
            consent: .init(
                transcriptIncluded: options.includeTranscript,
                audioIncluded: options.includeAudio
            ),
            session: .init(
                id: request.session.id,
                recordingDuration: request.session.recordingDuration,
                processingDuration: request.result.totalProcessingDuration,
                insertionSucceeded: request.result.insertionSucceeded,
                failureCode: request.failureCode
            ),
            runtime: .init(
                providerIdentifier: request.result.providerIdentifier,
                modelIdentifier: request.result.modelIdentifier,
                modelSHA256: request.modelSHA256,
                language: request.result.language
            ),
            transcript: transcript,
            audio: audio
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    private func validate(
        request: IssueBundleRequest,
        options: IssueBundleOptions
    ) throws {
        let boundedIdentifiers = [
            request.result.providerIdentifier,
            request.result.modelIdentifier,
            request.result.language,
            appVersion,
            operatingSystem,
            architecture,
        ]
        guard boundedIdentifiers.allSatisfy({ $0.isEmpty == false && $0.utf8.count <= 1_024 }),
              request.result.sessionID == request.session.id,
              request.session.recordingDuration.isFinite,
              request.result.totalProcessingDuration.isFinite
        else { throw IssueBundleError.invalidMetadata }
        if let failureCode = request.failureCode {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
            guard failureCode.isEmpty == false,
                  failureCode.count <= 100,
                  failureCode.unicodeScalars.allSatisfy(allowed.contains)
            else { throw IssueBundleError.invalidMetadata }
        }
        if let digest = request.modelSHA256 {
            let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            guard digest.count == 64, digest.unicodeScalars.allSatisfy(hex.contains) else {
                throw IssueBundleError.invalidMetadata
            }
        }
        if options.includeTranscript {
            guard request.result.rawTranscript.utf8.count <= Self.maximumTranscriptBytes,
                  request.result.finalTranscript.utf8.count <= Self.maximumTranscriptBytes
            else { throw IssueBundleError.transcriptTooLarge }
        }
    }

    private static var currentArchitecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}
