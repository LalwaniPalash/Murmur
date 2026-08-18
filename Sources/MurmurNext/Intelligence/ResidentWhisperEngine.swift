#if MURMUR_RESIDENT_WHISPER
import CWhisper
import Foundation

actor ResidentWhisperEngine: LocalTranscriptionEngine {
    private var context: WhisperContextReference?
    private var loadedModelPath: String?
    private var didLoadBackends = false
    private let operations = SerialOperationQueue()
    private var activeAbortState: WhisperAbortState?

    deinit {
        if let context {
            whisper_free(context.pointer)
        }
    }

    /// `whisper_context` is not thread-safe (see `whisper.h`), so every entry point that
    /// reads or frees it goes through one shared queue. Both paths matter: two overlapping
    /// `whisper_full` calls corrupt decoding, and a model change that calls `whisper_free`
    /// while a pass is still running is a use-after-free.
    func warmup(model: LocalWhisperModel) async throws {
        try await operations.run { [self] in try await loadContext(for: model) }
    }

    func transcribe(_ request: LocalTranscriptionRequest) async throws -> LocalTranscriptionResult {
        try await operations.run { [self] in try await performTranscription(request) }
    }

    private func loadContext(for model: LocalWhisperModel) throws {
        try ensureContext(for: model)
    }

    private func performTranscription(
        _ request: LocalTranscriptionRequest
    ) async throws -> LocalTranscriptionResult {
        let clock = ContinuousClock()
        let startedAt = clock.now

        try ensureContext(for: request.model)

        let primary = try await runPass(
            context: requireContext(),
            request: request,
            beamSize: max(request.beamSize, 1),
            bestOf: max(request.bestOf, 1),
            noSpeechThreshold: request.quietSpeechLikely ? 0.82 : 0.72,
            logProbabilityThreshold: -1.15,
            useFullAudioContext: request.forceFullAudioContext
        )

        var selected = primary
        var selectedBeamSize = max(request.beamSize, 1)

        let recordingDurationSeconds = Double(request.samples.count) / 16_000
        let looksTruncated = TranscriptQualityEvaluator.looksTruncated(
            primary.text,
            recordingDurationSeconds: recordingDurationSeconds
        )
        if request.quietSpeechLikely || TranscriptQualityEvaluator.shouldRetry(
            primary.text,
            recordingDurationSeconds: recordingDurationSeconds
        ) {
            let sensitiveBeamSize = max(request.beamSize, 8)
            let sensitiveBestOf = max(request.bestOf, 8)
            do {
                let sensitive = try await runPass(
                    context: requireContext(),
                    request: request,
                    beamSize: sensitiveBeamSize,
                    bestOf: sensitiveBestOf,
                    noSpeechThreshold: 0.90,
                    logProbabilityThreshold: -1.45,
                    useFullAudioContext: looksTruncated
                )
                if TranscriptQualityEvaluator.score(sensitive.text) > TranscriptQualityEvaluator.score(primary.text) {
                    selected = sensitive
                    selectedBeamSize = sensitiveBeamSize
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Preserve the primary pass when the fallback pass fails.
            }
        }

        let selectedText = TranscriptQualityEvaluator.collapsingRepeatedPhrase(selected.text)
        guard selectedText.isEmpty == false else { throw LocalTranscriptionError.emptyTranscript }
        return LocalTranscriptionResult(
            text: selectedText,
            usedBeamSize: selectedBeamSize,
            elapsed: startedAt.duration(to: clock.now),
            timeRanges: selected.timeRanges
        )
    }

    /// Deliberately not serialized: cancellation must reach an in-flight pass immediately
    /// rather than queueing behind the very operation it is trying to stop.
    func cancel() {
        activeAbortState?.requestCancellation()
    }

    private func ensureContext(for model: LocalWhisperModel) throws {
        guard FileManager.default.fileExists(atPath: model.fileURL.path) else {
            throw LocalTranscriptionError.modelUnavailable
        }

        let runtime = try requireRuntime()
        try loadBackendsIfNeeded(from: runtime)

        let modelPath = model.fileURL.standardizedFileURL.path
        if loadedModelPath == modelPath, context != nil {
            return
        }

        if let context {
            whisper_free(context.pointer)
            self.context = nil
            loadedModelPath = nil
        }

        var parameters = whisper_context_default_params()
        parameters.use_gpu = true
        parameters.flash_attn = true

        let pointer = model.fileURL.path.withCString { modelPathPointer in
            whisper_init_from_file_with_params(modelPathPointer, parameters)
        }

        guard let pointer else {
            throw LocalTranscriptionError.processFailed(
                exitCode: -1,
                message: "Unable to initialize the resident Whisper context."
            )
        }

        context = WhisperContextReference(pointer: pointer)
        loadedModelPath = modelPath
    }

    private func loadBackendsIfNeeded(from runtime: WhisperRuntimeLocation) throws {
        guard didLoadBackends == false else { return }
        guard FileManager.default.fileExists(atPath: runtime.backendDirectory.path) else {
            throw LocalTranscriptionError.runtimeUnavailable
        }
        runtime.backendDirectory.path.withCString { backendPath in
            ggml_backend_load_all_from_path(backendPath)
        }
        didLoadBackends = true
    }

    private func requireRuntime() throws -> WhisperRuntimeLocation {
        guard let runtime = WhisperRuntimeResolver.resolve() else {
            throw LocalTranscriptionError.runtimeUnavailable
        }
        return runtime
    }

    private func requireContext() throws -> WhisperContextReference {
        guard let context else {
            throw LocalTranscriptionError.processFailed(
                exitCode: -1,
                message: "The resident Whisper context is not initialized."
            )
        }
        return context
    }

    private func runPass(
        context: WhisperContextReference,
        request: LocalTranscriptionRequest,
        beamSize: Int,
        bestOf: Int,
        noSpeechThreshold: Float,
        logProbabilityThreshold: Float,
        useFullAudioContext: Bool = false
    ) async throws -> ResidentPassResult {
        let abortState = WhisperAbortState()
        activeAbortState = abortState
        defer {
            if activeAbortState === abortState { activeAbortState = nil }
        }
        // `serialized` guarantees this is the only pass touching the context, so the
        // detached task needs no further gating of its own.
        return try await Task.detached(priority: .userInitiated) {
            try ResidentWhisperEngine.executePass(
                context: context,
                samples: request.samples,
                language: request.language,
                prompt: request.prompt,
                beamSize: beamSize,
                bestOf: bestOf,
                noSpeechThreshold: noSpeechThreshold,
                logProbabilityThreshold: logProbabilityThreshold,
                useFullAudioContext: useFullAudioContext,
                abortState: abortState
            )
        }.value
    }

    private static func executePass(
        context: WhisperContextReference,
        samples: [Float],
        language: String,
        prompt: String?,
        beamSize: Int,
        bestOf: Int,
        noSpeechThreshold: Float,
        logProbabilityThreshold: Float,
        useFullAudioContext: Bool,
        abortState: WhisperAbortState
    ) throws -> ResidentPassResult {
        let strategy: whisper_sampling_strategy = beamSize > 1 ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY
        var parameters = whisper_full_default_params(strategy)
        parameters.print_progress = false
        parameters.print_realtime = false
        parameters.print_timestamps = false
        parameters.print_special = false
        parameters.no_timestamps = false
        parameters.suppress_nst = true
        parameters.no_context = true
        parameters.detect_language = false
        parameters.n_threads = Int32(max(ProcessInfo.processInfo.activeProcessorCount / 2, 2))
        parameters.audio_ctx = useFullAudioContext
            ? 0
            : Int32(WhisperAudioContextPolicy.audioContext(forSampleCount: samples.count))
        parameters.no_speech_thold = noSpeechThreshold
        parameters.logprob_thold = logProbabilityThreshold
        parameters.abort_callback = residentWhisperAbortCallback
        parameters.abort_callback_user_data = Unmanaged.passUnretained(abortState).toOpaque()
        if strategy == WHISPER_SAMPLING_GREEDY {
            parameters.greedy.best_of = Int32(max(bestOf, 1))
        } else {
            parameters.beam_search.beam_size = Int32(max(beamSize, 1))
        }

        let promptText = prompt?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(2_000)
        let normalizedPrompt = promptText.map(String.init)
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "en"
            : language

        let whisperResult = normalizedLanguage.withCString { languagePointer in
            parameters.language = languagePointer
            return withOptionalCString(normalizedPrompt) { promptPointer in
                parameters.initial_prompt = promptPointer
                return samples.withUnsafeBufferPointer { sampleBuffer in
                    whisper_full(
                        context.pointer,
                        parameters,
                        sampleBuffer.baseAddress,
                        Int32(sampleBuffer.count)
                    )
                }
            }
        }

        if abortState.isCancellationRequested {
            throw CancellationError()
        }

        guard whisperResult == 0 else {
            throw LocalTranscriptionError.processFailed(
                exitCode: whisperResult,
                message: "Resident Whisper transcription failed."
            )
        }

        let segmentCount = Int(whisper_full_n_segments(context.pointer))
        let text = (0..<segmentCount)
            .compactMap { index -> String? in
                guard let segment = whisper_full_get_segment_text(context.pointer, Int32(index)) else { return nil }
                return String(cString: segment).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let timeRanges = (0..<segmentCount).map { index in
            TranscriptionTimeRange(
                startSeconds: Double(whisper_full_get_segment_t0(context.pointer, Int32(index))) * 0.01,
                endSeconds: Double(whisper_full_get_segment_t1(context.pointer, Int32(index))) * 0.01
            )
        }
        return ResidentPassResult(text: text, timeRanges: timeRanges)
    }
}

private struct ResidentPassResult: Sendable {
    let text: String
    let timeRanges: [TranscriptionTimeRange]
}

private struct WhisperContextReference: @unchecked Sendable {
    let pointer: OpaquePointer
}

private final class WhisperAbortState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationRequested = false

    var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    func requestCancellation() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
    }
}

private func residentWhisperAbortCallback(_ data: UnsafeMutableRawPointer?) -> Bool {
    guard let data else { return false }
    return Unmanaged<WhisperAbortState>.fromOpaque(data).takeUnretainedValue().isCancellationRequested
}

private func withOptionalCString<Result>(
    _ string: String?,
    _ body: (UnsafePointer<CChar>?) throws -> Result
) rethrows -> Result {
    guard let string, string.isEmpty == false else {
        return try body(nil)
    }
    return try string.withCString(body)
}
#endif
