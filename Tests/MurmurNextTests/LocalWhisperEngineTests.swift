import Foundation
import Testing
@testable import MurmurNext

struct LocalWhisperEngineTests {
    @Test func waveEncoderProducesAValidMonoSixteenBitHeader() throws {
        let samples: [Float] = [-1, -0.5, 0, 0.5, 1]
        let data = try WaveFileEncoder.encode(samples: samples, sampleRate: 16_000)

        #expect(String(data: data[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
        #expect(String(data: data[12..<16], encoding: .ascii) == "fmt ")
        #expect(String(data: data[36..<40], encoding: .ascii) == "data")
        #expect(data.count == 44 + (samples.count * 2))
    }

    @Test(arguments: [
        (" Hello there.\n This is quiet.\n", "Hello there. This is quiet."),
        ("[BLANK_AUDIO]\n", ""),
        ("ggml_backend_load: loaded CPU backend\n Actual words.\n", "Actual words."),
        ("whisper_init: model loaded\nmain: processing\n", ""),
    ])
    func outputParserKeepsOnlySubstantiveTranscript(source: String, expected: String) {
        #expect(WhisperOutputParser.parse(source) == expected)
    }

    @Test func developmentRuntimeResolverFindsTheBundledAppleSiliconRuntime() {
        let location = WhisperRuntimeResolver.resolve()
        #expect(location != nil)
        #expect(location?.executableURL.lastPathComponent == "whisper-cli")
        #expect(location?.backendDirectory.lastPathComponent == "libexec")
    }

    @Test func runtimeProcessConfigurationUsesLibexecForNativeBackendDiscovery() {
        let root = URL(fileURLWithPath: "/tmp/Murmur Runtime", isDirectory: true)
        let runtime = WhisperRuntimeLocation(
            executableURL: root.appendingPathComponent("whisper-cli"),
            backendDirectory: root.appendingPathComponent("libexec", isDirectory: true)
        )

        let configuration = WhisperRuntimeProcessConfiguration(
            runtime: runtime,
            inheritedEnvironment: [
                "GGML_BACKEND_PATH": "/invalid/backend/directory",
                "MURMUR_TEST_VALUE": "preserved",
            ]
        )

        #expect(configuration.currentDirectoryURL == runtime.backendDirectory)
        #expect(configuration.environment["GGML_BACKEND_PATH"] == nil)
        #expect(configuration.environment["MURMUR_TEST_VALUE"] == "preserved")
    }

    @Test func unexpectedRuntimeSignalIsNotReportedAsUserCancellation() {
        let unexpected = WhisperProcessTermination.classify(
            reason: .uncaughtSignal,
            status: 6,
            standardError: "GGML_ASSERT(device) failed",
            cancellationRequested: false
        )
        let requested = WhisperProcessTermination.classify(
            reason: .uncaughtSignal,
            status: 15,
            standardError: "",
            cancellationRequested: true
        )

        #expect(unexpected == .failed(exitCode: 6, message: "GGML_ASSERT(device) failed"))
        #expect(requested == .cancelled)
    }

    @Test func modelCatalogRecognizesOnlyExpectedGGMLFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-model-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("ggml-large-v3-turbo.bin"))
        try Data([4]).write(to: directory.appendingPathComponent("notes.txt"))
        try Data([5]).write(to: directory.appendingPathComponent("damaged.bin.partial"))

        let models = try LocalWhisperModelCatalog(directory: directory).installedModels()
        #expect(models.map(\.identifier) == ["large-v3-turbo"])
    }

    @Test func modelCatalogRemovesOnlyValidatedModelPaths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-model-removal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let modelURL = directory.appendingPathComponent("ggml-small.en.bin")
        try Data([1]).write(to: modelURL)
        let catalog = LocalWhisperModelCatalog(directory: directory)

        try catalog.removeModel(identifier: "small.en")
        #expect(FileManager.default.fileExists(atPath: modelURL.path) == false)
        #expect(throws: (any Error).self) {
            try catalog.removeModel(identifier: "../../outside")
        }
    }

    @Test func candidateScoringRejectsArtifactsAndRepeatedHallucinations() {
        #expect(TranscriptQualityEvaluator.shouldRetry("Thank you you you"))
        #expect(TranscriptQualityEvaluator.shouldRetry("[BLANK_AUDIO]"))
        #expect(TranscriptQualityEvaluator.shouldRetry("") )
        #expect(TranscriptQualityEvaluator.shouldRetry("yes") == false)
        #expect(TranscriptQualityEvaluator.shouldRetry("send it") == false)
        #expect(TranscriptQualityEvaluator.score("The quiet sentence is complete.") > TranscriptQualityEvaluator.score("quiet quiet quiet"))
    }

    @Test func implausiblySparseTranscriptRetriesWithoutPenalizingNormalShortDictation() {
        #expect(
            TranscriptQualityEvaluator.looksTruncated(
                "give a",
                recordingDurationSeconds: 8
            )
        )
        #expect(
            TranscriptQualityEvaluator.shouldRetry(
                "give a",
                recordingDurationSeconds: 8
            )
        )
        #expect(
            TranscriptQualityEvaluator.looksTruncated(
                "give a",
                recordingDurationSeconds: 3
            )
        )
        #expect(
            TranscriptQualityEvaluator.looksTruncated(
                "give this a try",
                recordingDurationSeconds: 3
            ) == false
        )
        #expect(
            TranscriptQualityEvaluator.looksTruncated(
                "Please send the revised schedule after lunch.",
                recordingDurationSeconds: 8
            ) == false
        )
    }

    @Test func sparseThreeSecondTranscriptRetriesBecauseItCanHideACutOffEnding() {
        #expect(TranscriptQualityEvaluator.shouldRetry(
            "go ahead",
            recordingDurationSeconds: 3.2
        ))
        #expect(TranscriptQualityEvaluator.shouldRetry(
            "go ahead and start with that implementation",
            recordingDurationSeconds: 3.2
        ) == false)
    }

    @Test func collapsesOnlyARepeatedWholePhrase() {
        #expect(TranscriptQualityEvaluator.collapsingRepeatedPhrase(
            "You go ahead and start with that implementation you go ahead and start with that implementation"
        ) == "You go ahead and start with that implementation")
        #expect(TranscriptQualityEvaluator.collapsingRepeatedPhrase("very very useful") == "very very useful")
    }

    @Test func audioContextTruncationScalesWithRealBufferLength() {
        #expect(WhisperAudioContextPolicy.audioContext(forSampleCount: 1_600) == 256)
        #expect(WhisperAudioContextPolicy.audioContext(forSampleCount: 48_000) == 278)
        #expect(WhisperAudioContextPolicy.audioContext(forSampleCount: 464_000) == 1_500)
        #expect(WhisperAudioContextPolicy.audioContext(forSampleCount: 480_000) == 0)
    }
}
