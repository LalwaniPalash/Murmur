#if MURMUR_RESIDENT_WHISPER
import Foundation
import MurmurQualityCore
import Testing

@testable import MurmurNext

/// Exercises the real resident Whisper context end to end.
///
/// Every other engine test in this suite runs against a stub, so nothing else here
/// proves that `whisper_full` is actually reachable, that the backend plugins load,
/// or that the context genuinely survives between calls. These tests need a staged
/// runtime and a verified installed model, so they skip cleanly on machines that
/// have neither rather than failing the suite.
/// Serialized: each test builds its own resident context holding the full model, so
/// running them in parallel loads the model twice and makes two Metal command queues
/// contend for the GPU. That inflates the latency assertions into noise.
@Suite(.serialized)
struct ResidentWhisperEngineIntegrationTests {
    /// A short spoken phrase synthesized at 16 kHz mono, matching the format the
    /// dictation pipeline hands to the engine.
    private static func makeSpeechSamples(_ phrase: String) throws -> [Float]? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-resident-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let aiffURL = directory.appendingPathComponent("speech.aiff")
        let wavURL = directory.appendingPathComponent("speech.wav")

        guard run("/usr/bin/say", ["-v", "Samantha", "-o", aiffURL.path, phrase]),
              run("/usr/bin/afconvert", [
                  "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiffURL.path, wavURL.path,
              ])
        else { return nil }

        let data = try Data(contentsOf: wavURL)
        guard data.count > 44 else { return nil }
        return data.dropFirst(44).withUnsafeBytes { raw -> [Float] in
            raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32_768 }
        }
    }

    private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func installedModel() throws -> LocalWhisperModel? {
        guard WhisperRuntimeResolver.resolve() != nil else { return nil }
        return try LocalWhisperModelCatalog().installedModels().first
    }

    @Test func residentContextTranscribesRealSpeechAndSurvivesBetweenCalls() async throws {
        guard let model = try Self.installedModel(),
              let samples = try Self.makeSpeechSamples("Send the quarterly report to Michael.")
        else { return }

        let engine = ResidentWhisperEngine()
        try await engine.warmup(model: model)

        func transcribe() async throws -> LocalTranscriptionResult {
            try await engine.transcribe(
                LocalTranscriptionRequest(
                    samples: samples,
                    model: model,
                    language: "en",
                    prompt: nil,
                    beamSize: 1,
                    bestOf: 1
                )
            )
        }

        let first = try await transcribe()
        let second = try await transcribe()

        let normalize: (String) -> String = {
            $0.lowercased().filter { $0.isLetter || $0.isWhitespace }
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }

        #expect(normalize(first.text).contains("quarterly report"))
        // A resident context must produce stable output across calls; a reloaded or
        // corrupted context is the failure this guards against.
        #expect(normalize(first.text) == normalize(second.text))

        // The second call reuses the warmed context, so it must not pay model load
        // or Metal initialization again. Measured baseline: a reload costs >250ms on
        // its own, so a generous ceiling still catches a regression to per-call loading.
        #expect(second.elapsed < .seconds(1))
    }

    @Test func shortUtteranceTranscribesWithinTheLatencyBudget() async throws {
        guard let model = try Self.installedModel(),
              let samples = try Self.makeSpeechSamples("Yes, that works.")
        else { return }

        let engine = ResidentWhisperEngine()
        try await engine.warmup(model: model)
        _ = try? await engine.transcribe(
            LocalTranscriptionRequest(
                samples: samples, model: model, language: "en",
                prompt: nil, beamSize: 1, bestOf: 1
            )
        )

        let result = try await engine.transcribe(
            LocalTranscriptionRequest(
                samples: samples, model: model, language: "en",
                prompt: nil, beamSize: 1, bestOf: 1
            )
        )

        #expect(result.text.isEmpty == false)
        // Short full-recording passes still benefit from truncating Whisper's padded
        // encoder context to the actual capture length.
        #expect(result.elapsed < .milliseconds(500))
    }

    /// Covers the optimized sub-30-second audio-context path. A fluent prefix is not a
    /// complete transcript when the final clause disappeared.
    @Test func mediumUtteranceKeepsItsBeginningAndEnd() async throws {
        guard let model = try Self.installedModel(),
              let samples = try Self.makeSpeechSamples(
                  "Give a detailed explanation of the schedule, include the budget review, and finish with the word sapphire."
              )
        else { return }
        #expect(samples.count < 30 * 16_000)

        let engine = ResidentWhisperEngine()
        try await engine.warmup(model: model)
        let result = try await engine.transcribe(
            LocalTranscriptionRequest(
                samples: samples,
                model: model,
                language: "en",
                prompt: nil,
                beamSize: 1,
                bestOf: 1
            )
        )

        let text = result.text.lowercased()
        #expect(text.contains("detailed explanation"))
        #expect(text.contains("sapphire"))
    }

    /// A long utterance with pauses must be decoded as one authoritative recording and keep
    /// content from its beginning, middle, and end.
    @MainActor
    @Test func longPausedUtteranceKeepsEveryPhrase() async throws {
        guard let model = try Self.installedModel(),
              let opening = try Self.makeSpeechSamples(
                  "I wanted to walk through the quarterly numbers with the whole team before Friday."
              ),
              let middle = try Self.makeSpeechSamples(
                  "The revenue line came in ahead of the forecast we published back in the spring."
              ),
              let closing = try Self.makeSpeechSamples("So let us ship it.")
        else { return }

        let engine = ResidentWhisperEngine()
        // The app pays this once in the background at launch, so steady-state dictation
        // never sees it. Same reason the provider below hands back the model directly
        // rather than re-verifying it.
        try await engine.warmup(model: model)

        let audio = TestAudioInput()
        let insertion = TestInsertionService()
        var performance: [DictationPerformanceSample] = []
        let orchestrator = DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: engine,
            modelProvider: PreverifiedModelProvider(model: model),
            insertionService: insertion,
            personalization: { ([], []) },
            historyHandler: { _ in },
            performanceHandler: { performance.append($0) }
        )

        let pause = [Float](repeating: 0, count: 16_000)
        try orchestrator.begin(mode: .pushToTalk)

        audio.emit(audio: opening)
        audio.emit(audio: pause)
        audio.emit(audio: middle)
        audio.emit(audio: pause)
        audio.emit(audio: closing)
        await orchestrator.finish()

        #expect(orchestrator.phase == .completed)
        let inserted = insertion.insertedTexts.first ?? ""
        #expect(inserted.lowercased().contains("quarterly"))
        #expect(inserted.lowercased().contains("forecast"))
        #expect(inserted.lowercased().contains("ship"))
        try Self.writePipelineBenchmarkIfRequested(performance, model: model)
    }

    private static func writePipelineBenchmarkIfRequested(
        _ performance: [DictationPerformanceSample],
        model: LocalWhisperModel
    ) throws {
        guard let path = ProcessInfo.processInfo.environment["MURMUR_QUALITY_REPORT_DIR"],
              path.isEmpty == false
        else { return }
        let samples = performance.compactMap { sample -> BenchmarkSample? in
            guard let stage = BenchmarkStage(rawValue: sample.stage.rawValue) else { return nil }
            return BenchmarkSample(
                stage: stage,
                recordingDurationSeconds: sample.recordingDurationSeconds,
                elapsedMilliseconds: sample.elapsedMilliseconds,
                hardwareIdentifier: BenchmarkEnvironment.hardwareIdentifier,
                modelIdentifier: model.identifier
            )
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try QualityJSON.encoder.encode(samples).write(
            to: directory.appendingPathComponent("pipeline-benchmark-samples.json"),
            options: [.atomic]
        )
    }
}

private struct PreverifiedModelProvider: WhisperModelProviding {
    let model: LocalWhisperModel

    func selectedModel(preferredIdentifier: String?) async throws -> LocalWhisperModel { model }
}
#endif
