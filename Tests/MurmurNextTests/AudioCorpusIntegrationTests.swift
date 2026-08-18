import Foundation
import MurmurQualityCore
import Testing

@testable import MurmurNext

@Suite(.serialized)
struct AudioCorpusIntegrationTests {
    @Test func residentEnginePreservesRequiredSpeechAcrossVersionedCorpus() async throws {
        let manifestURL = try #require(Bundle.module.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "Fixtures/AudioCorpus"
        ))
        let baseDirectory = manifestURL.deletingLastPathComponent()
        let manifest = try CorpusManifestValidator.validate(
            CorpusManifestLoader.load(from: manifestURL),
            baseDirectory: baseDirectory
        )
        let benchmarkCollector = BenchmarkCollector()

#if MURMUR_RESIDENT_WHISPER
        let model = try Self.installedModel()
        let engine = ResidentWhisperEngine()
        if let model {
            let clock = ContinuousClock()
            let warmupStartedAt = clock.now
            try await engine.warmup(model: model)
            await benchmarkCollector.append(BenchmarkSample(
                stage: .warmup,
                recordingDurationSeconds: 0,
                elapsedMilliseconds: BenchmarkEnvironment.milliseconds(
                    warmupStartedAt.duration(to: clock.now)
                ),
                hardwareIdentifier: BenchmarkEnvironment.hardwareIdentifier,
                modelIdentifier: model.identifier
            ))
        }
        let report = await CorpusRunner.run(
            manifest: manifest,
            baseDirectory: baseDirectory,
            modelIdentifier: model?.identifier ?? "unavailable",
            modelAvailable: model != nil
        ) { audioURL, fixture in
            guard let model else { throw LocalTranscriptionError.modelUnavailable }
            let audio = try WaveAudioDecoder.decode(contentsOf: audioURL)
            guard audio.sampleRate == 16_000 else {
                throw CorpusRunnerError.audioResolutionFailed(
                    "Expected 16000 Hz audio, received \(audio.sampleRate) Hz."
                )
            }
            let result = try await engine.transcribe(LocalTranscriptionRequest(
                samples: audio.samples,
                model: model,
                language: fixture.language,
                prompt: nil,
                beamSize: 1,
                bestOf: 1,
                quietSpeechLikely: fixture.speechCondition == .quiet || fixture.speechCondition == .whisper
            ))
            await benchmarkCollector.append(BenchmarkSample(
                stage: .transcription,
                recordingDurationSeconds: Double(audio.samples.count) / Double(audio.sampleRate),
                elapsedMilliseconds: BenchmarkEnvironment.milliseconds(result.elapsed),
                hardwareIdentifier: BenchmarkEnvironment.hardwareIdentifier,
                modelIdentifier: model.identifier
            ))
            return result.text
        }
#else
        let report = await CorpusRunner.run(
            manifest: manifest,
            baseDirectory: baseDirectory,
            modelIdentifier: "runtime-unavailable",
            modelAvailable: false
        ) { _, _ in
            Issue.record("Transcription cannot run without the staged resident runtime.")
            return ""
        }
#endif

        try Self.writeReportsIfRequested(
            corpus: report,
            benchmarkSamples: await benchmarkCollector.values()
        )
        if report.skippedFixtureCount > 0 {
            #expect(report.skippedFixtureCount == manifest.fixtures.count)
            #expect(report.completedFixtureCount == 0)
        } else {
            #expect(report.completedFixtureCount == manifest.fixtures.count)
            #expect(report.failedFixtureCount == 0)
        }
    }

#if MURMUR_RESIDENT_WHISPER
    private static func installedModel() throws -> LocalWhisperModel? {
        guard WhisperRuntimeResolver.resolve() != nil else { return nil }
        return try LocalWhisperModelCatalog().installedModels().first
    }
#endif

    private static func writeReportsIfRequested(
        corpus: CorpusQualityReport,
        benchmarkSamples: [BenchmarkSample]
    ) throws {
        guard let path = ProcessInfo.processInfo.environment["MURMUR_QUALITY_REPORT_DIR"],
              path.isEmpty == false
        else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try QualityJSON.encoder.encode(corpus).write(
            to: directory.appendingPathComponent("corpus-quality.json"),
            options: [.atomic]
        )
        try QualityJSON.encoder.encode(benchmarkSamples).write(
            to: directory.appendingPathComponent("benchmark-samples.json"),
            options: [.atomic]
        )
        try QualityJSON.encoder.encode(BenchmarkSummarizer.summarize(benchmarkSamples)).write(
            to: directory.appendingPathComponent("benchmark-report.json"),
            options: [.atomic]
        )
    }
}

private actor BenchmarkCollector {
    private var samples: [BenchmarkSample] = []

    func append(_ sample: BenchmarkSample) {
        samples.append(sample)
    }

    func values() -> [BenchmarkSample] {
        samples
    }
}
