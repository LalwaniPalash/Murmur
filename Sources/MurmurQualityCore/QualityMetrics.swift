import Foundation

public struct TranscriptScore: Codable, Equatable, Sendable {
    public let expectedWordCount: Int
    public let actualWordCount: Int
    public let wordSubstitutions: Int
    public let wordInsertions: Int
    public let wordDeletions: Int
    public let wordErrorRate: Double
    public let characterErrorRate: Double

    public init(
        expectedWordCount: Int,
        actualWordCount: Int,
        wordSubstitutions: Int,
        wordInsertions: Int,
        wordDeletions: Int,
        wordErrorRate: Double,
        characterErrorRate: Double
    ) {
        self.expectedWordCount = expectedWordCount
        self.actualWordCount = actualWordCount
        self.wordSubstitutions = wordSubstitutions
        self.wordInsertions = wordInsertions
        self.wordDeletions = wordDeletions
        self.wordErrorRate = wordErrorRate
        self.characterErrorRate = characterErrorRate
    }

    public static let perfect = TranscriptScore(
        expectedWordCount: 1,
        actualWordCount: 1,
        wordSubstitutions: 0,
        wordInsertions: 0,
        wordDeletions: 0,
        wordErrorRate: 0,
        characterErrorRate: 0
    )
}

public enum TranscriptScorer {
    public static func score(expected: String, actual: String) -> TranscriptScore {
        let expectedTokens = TranscriptNormalizer.tokens(in: expected)
        let actualTokens = TranscriptNormalizer.tokens(in: actual)
        let alignment = TranscriptAligner.align(expected: expected, actual: actual)
        let substitutions = alignment.operations.filter { $0.kind == .substitution }.count
        let insertions = alignment.operations.filter { $0.kind == .insertion }.count
        let deletions = alignment.operations.filter { $0.kind == .deletion }.count
        return TranscriptScore(
            expectedWordCount: expectedTokens.count,
            actualWordCount: actualTokens.count,
            wordSubstitutions: substitutions,
            wordInsertions: insertions,
            wordDeletions: deletions,
            wordErrorRate: alignment.wordErrorRate,
            characterErrorRate: alignment.characterErrorRate
        )
    }
}

public enum CorpusFixtureStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
    case skipped
}

public struct CorpusFixtureResult: Codable, Equatable, Sendable {
    public let fixtureID: String
    public let model: String
    public let language: String
    public let speechCondition: SpeechCondition
    public let status: CorpusFixtureStatus
    public let score: TranscriptScore?
    public let completeness: TranscriptCompletenessResult?
    public let reason: String?

    public static func passed(
        fixtureID: String,
        model: String,
        language: String,
        speechCondition: SpeechCondition,
        score: TranscriptScore,
        completeness: TranscriptCompletenessResult? = nil
    ) -> CorpusFixtureResult {
        CorpusFixtureResult(
            fixtureID: fixtureID,
            model: model,
            language: language,
            speechCondition: speechCondition,
            status: .passed,
            score: score,
            completeness: completeness,
            reason: nil
        )
    }

    public static func failed(
        fixtureID: String,
        model: String,
        language: String,
        speechCondition: SpeechCondition,
        score: TranscriptScore? = nil,
        completeness: TranscriptCompletenessResult? = nil,
        reason: String
    ) -> CorpusFixtureResult {
        CorpusFixtureResult(
            fixtureID: fixtureID,
            model: model,
            language: language,
            speechCondition: speechCondition,
            status: .failed,
            score: score,
            completeness: completeness,
            reason: reason
        )
    }

    public static func skipped(
        fixtureID: String,
        model: String,
        language: String,
        speechCondition: SpeechCondition,
        reason: String
    ) -> CorpusFixtureResult {
        CorpusFixtureResult(
            fixtureID: fixtureID,
            model: model,
            language: language,
            speechCondition: speechCondition,
            status: .skipped,
            score: nil,
            completeness: nil,
            reason: reason
        )
    }
}

public struct CorpusQualityGroup: Codable, Equatable, Sendable {
    public let model: String
    public let language: String
    public let speechCondition: SpeechCondition
    public let completedFixtureCount: Int
    public let meanWordErrorRate: Double
    public let meanCharacterErrorRate: Double
}

public struct CorpusQualityReport: Codable, Equatable, Sendable {
    public let format: String
    public let version: Int
    public let results: [CorpusFixtureResult]
    public let groups: [CorpusQualityGroup]
    public let completedFixtureCount: Int
    public let failedFixtureCount: Int
    public let skippedFixtureCount: Int

    public init(
        results: [CorpusFixtureResult],
        format: String = "murmur-corpus-quality",
        version: Int = 1
    ) {
        self.format = format
        self.version = version
        self.results = results.sorted { $0.fixtureID < $1.fixtureID }
        completedFixtureCount = results.filter { $0.status != .skipped }.count
        failedFixtureCount = results.filter { $0.status == .failed }.count
        skippedFixtureCount = results.filter { $0.status == .skipped }.count

        struct Key: Hashable {
            let model: String
            let language: String
            let speechCondition: SpeechCondition
        }
        let scored = results.filter { $0.score != nil }
        let grouped = Dictionary(grouping: scored) {
            Key(model: $0.model, language: $0.language, speechCondition: $0.speechCondition)
        }
        groups = grouped.map { key, values in
            let scores = values.compactMap(\.score)
            return CorpusQualityGroup(
                model: key.model,
                language: key.language,
                speechCondition: key.speechCondition,
                completedFixtureCount: scores.count,
                meanWordErrorRate: scores.map(\.wordErrorRate).mean,
                meanCharacterErrorRate: scores.map(\.characterErrorRate).mean
            )
        }.sorted {
            ($0.model, $0.language, $0.speechCondition.rawValue)
                < ($1.model, $1.language, $1.speechCondition.rawValue)
        }
    }
}

private extension Array where Element == Double {
    var mean: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
}

public struct ResolvedCorpusAudio: Sendable {
    public let url: URL
    public let cleanupDirectory: URL?

    public init(url: URL, cleanupDirectory: URL? = nil) {
        self.url = url
        self.cleanupDirectory = cleanupDirectory
    }

    public func cleanUp() {
        guard let cleanupDirectory else { return }
        try? FileManager.default.removeItem(at: cleanupDirectory)
    }
}

public enum CorpusAudioResolver {
    public static func resolve(_ fixture: AudioCorpusFixture, baseDirectory: URL) throws -> ResolvedCorpusAudio {
        switch fixture.source {
        case .audioFile(let path):
            return ResolvedCorpusAudio(url: baseDirectory.appendingPathComponent(path))
        case .synthesis(let text, let voice, let rate):
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("murmur-corpus-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                let aiffURL = directory.appendingPathComponent("speech.aiff")
                let wavURL = directory.appendingPathComponent("speech.wav")
                try run("/usr/bin/say", [
                    "-v", voice, "-r", String(rate), "-o", aiffURL.path, text,
                ])
                try run("/usr/bin/afconvert", [
                    "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiffURL.path, wavURL.path,
                ])
                return ResolvedCorpusAudio(url: wavURL, cleanupDirectory: directory)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown process error"
            throw CorpusRunnerError.audioResolutionFailed(message)
        }
    }
}

public enum CorpusRunnerError: Error, LocalizedError, Sendable {
    case audioResolutionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .audioResolutionFailed(let message): "Audio fixture generation failed: \(message)"
        }
    }
}

public enum CorpusRunner {
    public typealias Transcribe = @Sendable (URL, AudioCorpusFixture) async throws -> String

    public static func run(
        manifest: AudioCorpusManifest,
        baseDirectory: URL,
        modelIdentifier: String,
        modelAvailable: Bool,
        transcribe: Transcribe
    ) async -> CorpusQualityReport {
        guard modelAvailable else {
            return CorpusQualityReport(results: manifest.fixtures.map {
                .skipped(
                    fixtureID: $0.id,
                    model: modelIdentifier,
                    language: $0.language,
                    speechCondition: $0.speechCondition,
                    reason: "model unavailable"
                )
            })
        }

        var results: [CorpusFixtureResult] = []
        for fixture in manifest.fixtures {
            do {
                let audio = try CorpusAudioResolver.resolve(fixture, baseDirectory: baseDirectory)
                defer { audio.cleanUp() }
                let actual = try await transcribe(audio.url, fixture)
                let score = TranscriptScorer.score(expected: fixture.expectedTranscript, actual: actual)
                let completeness = TranscriptCompletenessAnalyzer.analyze(
                    expected: fixture.expectedTranscript,
                    actual: actual,
                    requiredPhrases: fixture.requiredPhrases,
                    protectedTokens: fixture.protectedTokens
                )
                if completeness.isComplete {
                    results.append(.passed(
                        fixtureID: fixture.id,
                        model: modelIdentifier,
                        language: fixture.language,
                        speechCondition: fixture.speechCondition,
                        score: score,
                        completeness: completeness
                    ))
                } else {
                    results.append(.failed(
                        fixtureID: fixture.id,
                        model: modelIdentifier,
                        language: fixture.language,
                        speechCondition: fixture.speechCondition,
                        score: score,
                        completeness: completeness,
                        reason: "required speech was not preserved"
                    ))
                }
            } catch {
                results.append(.failed(
                    fixtureID: fixture.id,
                    model: modelIdentifier,
                    language: fixture.language,
                    speechCondition: fixture.speechCondition,
                    reason: String(describing: error)
                ))
            }
        }
        return CorpusQualityReport(results: results)
    }
}
