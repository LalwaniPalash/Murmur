import Foundation
import Testing
@testable import MurmurNext

@MainActor
struct DictationFullRecordingTests {
    /// Pause-bounded decoding is not authoritative: Whisper can return plausible,
    /// non-empty text while omitting words, which gives the orchestrator no error signal
    /// that would trigger a fallback. The only safe final input is the full capture.
    @Test func pausedUtteranceUsesOneAuthoritativeFullBufferPass() async throws {
        let audio = TestAudioInput()
        let transcription = TestTranscriptionEngine(text: "The whole recording.")
        let insertion = TestInsertionService()
        let orchestrator = makeOrchestrator(
            audio: audio,
            transcription: transcription,
            insertion: insertion
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitSpeech(frames: 20)
        audio.emitSilence(frames: 8)
        audio.emitSpeech(frames: 10)
        await orchestrator.finish()

        let requests = await transcription.requests
        #expect(requests.count == 1)
        #expect(requests.first?.samples.count == 38 * 1_600)
        #expect(insertion.insertedTexts == ["The whole recording."])
    }

    /// The repair pass still sees one complete transcript, so a correction on opposite
    /// sides of a pause remains visible to it.
    @Test func repairsACorrectionThatStraddlesAPause() async throws {
        let audio = TestAudioInput()
        let transcription = TestTranscriptionEngine(text: "Meet Tuesday sorry, Wednesday at three.")
        let insertion = TestInsertionService()
        var history: [TranscriptRecord] = []
        let orchestrator = makeOrchestrator(
            audio: audio,
            transcription: transcription,
            insertion: insertion,
            historyHandler: { history.append($0) }
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitSpeech(frames: 20)
        audio.emitSilence(frames: 8)
        audio.emitSpeech(frames: 10)
        await orchestrator.finish()

        #expect(orchestrator.phase == .completed)
        #expect(insertion.insertedTexts == ["Meet Wednesday at three."])
        #expect(history.map(\.text) == ["Meet Wednesday at three."])
        #expect(await transcription.requests.count == 1)
    }

    /// Cancelling while `finish()` is suspended draining capture must read as cancelled.
    /// Without the post-drain guard the finalizer runs on an already-cancelled session,
    /// its state-machine transition throws, and the user sees a failure they never caused.
    @Test func cancellingWhileFinishIsDrainingReportsCancelledNotFailed() async throws {
        let audio = TestAudioInput()
        let insertion = TestInsertionService()
        let orchestrator = makeOrchestrator(
            audio: audio,
            transcription: TestTranscriptionEngine(text: "Should never appear."),
            insertion: insertion
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitSpeech(frames: 20)

        let finishing = Task { await orchestrator.finish() }
        await Task.yield()
        await orchestrator.cancel()
        await finishing.value

        #expect(orchestrator.phase == .cancelled)
        #expect(orchestrator.lastError == nil)
        #expect(insertion.insertedTexts.isEmpty)
    }

    @Test func shortUtterancesStillRunAsASinglePass() async throws {
        let audio = TestAudioInput()
        let transcription = TestTranscriptionEngine(text: "Yes.")
        let insertion = TestInsertionService()
        let orchestrator = makeOrchestrator(
            audio: audio,
            transcription: transcription,
            insertion: insertion
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitSpeech(frames: 5)
        await orchestrator.finish()

        #expect(await transcription.requests.count == 1)
        #expect(insertion.insertedTexts == ["Yes."])
    }

    @Test func cancellingDuringCaptureInsertsNothing() async throws {
        let audio = TestAudioInput()
        let transcription = TestTranscriptionEngine(text: "Should never appear.")
        let insertion = TestInsertionService()
        let orchestrator = makeOrchestrator(
            audio: audio,
            transcription: transcription,
            insertion: insertion
        )

        try orchestrator.begin(mode: .pushToTalk)
        audio.emitSpeech(frames: 20)
        audio.emitSilence(frames: 8)
        await orchestrator.cancel()

        #expect(orchestrator.phase == .cancelled)
        #expect(insertion.insertedTexts.isEmpty)
        #expect(await transcription.wasCancelled)
    }

    private func makeOrchestrator(
        audio: TestAudioInput,
        transcription: TestTranscriptionEngine,
        insertion: TestInsertionService = TestInsertionService(),
        historyHandler: @escaping @MainActor @Sendable (TranscriptRecord) -> Void = { _ in }
    ) -> DictationOrchestrator {
        DictationOrchestrator(
            audioInput: audio,
            transcriptionEngine: transcription,
            modelProvider: try! TestModelProvider(),
            insertionService: insertion,
            personalization: { ([], []) },
            historyHandler: historyHandler
        )
    }
}

struct DictationAudioProcessorTests {
    /// The processor keeps one uninterrupted session buffer even when speech is separated
    /// by a long silence.
    @Test func pausedCaptureKeepsEveryProcessedSample() async {
        let processor = DictationAudioProcessor()

        for index in 0..<55 {
            let isSpeech = index < 20 || index >= 45
            let samples = (0..<1_600).map { sampleIndex -> Float in
                isSpeech ? sin(2 * Float.pi * 180 * Float(sampleIndex) / 16_000) * 0.12 : 0
            }
            _ = await processor.ingest(
                AudioFrame(samples: samples, sampleRate: 16_000, capturedAt: .now)
            )
        }

        let all = await processor.allSamples()
        #expect(all.count == 55 * 1_600)
        #expect(await processor.totalSampleCount == 55 * 1_600)
    }
}
