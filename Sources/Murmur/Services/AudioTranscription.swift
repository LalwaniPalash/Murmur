import AVFoundation
import Foundation
import Speech
import OSLog

private let logger = Logger(subsystem: "com.murmur.app", category: "AudioTranscription")

protocol AudioCaptureServiceProtocol {
    func startCapture(
        bufferHandler: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void,
        levelHandler: @escaping (Double) -> Void
    ) throws
    func stopCapture() -> AudioMetrics
}

protocol TranscriptionEngine {
    var latestTranscript: String { get }
    func startTranscribing(
        localeIdentifier: String,
        partialHandler: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) throws
    func append(_ buffer: AVAudioPCMBuffer)
    func finish()
    func cancel()
}

final class LiveAudioCaptureService: AudioCaptureServiceProtocol {
    private let audioEngine = AVAudioEngine()
    private var startedAt: Date?
    private var peakPower: Double = -80
    private var averageAccumulator: Double = 0
    private var levelCount = 0
    private var sampleCount = 0

    func startCapture(
        bufferHandler: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void,
        levelHandler: @escaping (Double) -> Void
    ) throws {
        stopEngine()
        startedAt = Date()
        peakPower = -80
        averageAccumulator = 0
        levelCount = 0
        sampleCount = 0

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, time in
            bufferHandler(buffer, time)
            let level = Self.averagePowerLevel(for: buffer)
            self?.sampleCount += Int(buffer.frameLength)
            self?.peakPower = max(self?.peakPower ?? level, level)
            self?.averageAccumulator += level
            self?.levelCount += 1
            levelHandler(level)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopCapture() -> AudioMetrics {
        defer { stopEngine() }
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let average = levelCount > 0 ? averageAccumulator / Double(levelCount) : -80
        return AudioMetrics(
            averagePower: average,
            peakPower: peakPower,
            sampleCount: sampleCount,
            duration: duration
        )
    }

    private func stopEngine() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }

    private static func averagePowerLevel(for buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else {
            return -80
        }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return -80 }
        let values = UnsafeBufferPointer(start: channelData[0], count: frames)
        let meanSquare = values.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(frames)
        guard meanSquare > 0 else { return -80 }
        return 10 * log10(meanSquare)
    }
}

/// Adaptive transcription engine that selects between Whisper.cpp and Apple Speech.
/// Marked @unchecked Sendable because all state access is initiated by @MainActor-isolated DictationSessionManager.
/// The activeEngine switch is serialized through DictationSessionManager's phase transitions,
/// and callbacks dispatch back to MainActor via Task { @MainActor in }.
final class AdaptiveTranscriptionEngine: @unchecked Sendable, TranscriptionEngine {
    private let localEngine: WhisperCLITranscriptionEngine
    private let fallbackEngine: SpeechRecognizerTranscriptionEngine
    private var activeEngine: (any TranscriptionEngine)?

    init(modelManager: ModelManager, settingsStore: SettingsStore) {
        localEngine = WhisperCLITranscriptionEngine(modelManager: modelManager, settingsStore: settingsStore)
        fallbackEngine = SpeechRecognizerTranscriptionEngine()
    }

    var latestTranscript: String {
        activeEngine?.latestTranscript ?? localEngine.latestTranscript.nonEmpty ?? fallbackEngine.latestTranscript
    }

    func startTranscribing(
        localeIdentifier: String,
        partialHandler: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) throws {
        cancel()

        if localEngine.canTranscribe(localeIdentifier: localeIdentifier) {
            activeEngine = localEngine
            do {
                try localEngine.startTranscribing(
                    localeIdentifier: localeIdentifier,
                    partialHandler: partialHandler,
                    completion: completion
                )
                return
            } catch {
                activeEngine = nil
            }
        }

        activeEngine = fallbackEngine
        try fallbackEngine.startTranscribing(
            localeIdentifier: localeIdentifier,
            partialHandler: partialHandler,
            completion: completion
        )
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        activeEngine?.append(buffer)
    }

    func finish() {
        activeEngine?.finish()
    }

    func cancel() {
        activeEngine?.cancel()
        localEngine.cancel()
        fallbackEngine.cancel()
        activeEngine = nil
    }
}

/// Whisper.cpp command-line transcription engine.
/// Marked @unchecked Sendable because all access is initiated by @MainActor-isolated DictationSessionManager.
/// Mutable state (audioFile, audioURL, completion, partialHandler, currentProcess) is protected by stateLock for the audio capture/engine interaction.
/// Callbacks dispatch back to MainActor via Task { @MainActor in }.
final class WhisperCLITranscriptionEngine: @unchecked Sendable, TranscriptionEngine {
    private let modelManager: ModelManager
    private let settingsStore: SettingsStore
    private let stateLock = NSLock()

    private var audioFile: AVAudioFile?
    private var audioURL: URL?
    private var completion: ((Result<String, Error>) -> Void)?
    private var partialHandler: ((String) -> Void)?
    private var currentProcess: Process?
    private var activeLocaleIdentifier = Locale.autoupdatingCurrent.identifier
    private(set) var latestTranscript = ""

    init(modelManager: ModelManager, settingsStore: SettingsStore) {
        self.modelManager = modelManager
        self.settingsStore = settingsStore
    }

    func canTranscribe(localeIdentifier: String) -> Bool {
        runtimePath() != nil && selectedModel(localeIdentifier: localeIdentifier)?.storagePath != nil
    }

    func startTranscribing(
        localeIdentifier: String,
        partialHandler: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) throws {
        cancel()
        guard runtimePath() != nil else {
            throw NSError(domain: "Murmur.Transcription", code: 10, userInfo: [NSLocalizedDescriptionKey: "whisper-cli is not available."])
        }
        guard selectedModel(localeIdentifier: localeIdentifier)?.storagePath != nil else {
            throw NSError(domain: "Murmur.Transcription", code: 11, userInfo: [NSLocalizedDescriptionKey: "No local Whisper model is ready."])
        }

        self.partialHandler = partialHandler
        self.completion = completion
        self.latestTranscript = ""
        self.activeLocaleIdentifier = localeIdentifier

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-\(UUID().uuidString).wav")
        audioURL = tempURL
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        var writeError: Error?
        stateLock.lock()
        do {
            if audioFile == nil {
                guard let audioURL else {
                    stateLock.unlock()
                    return
                }
                audioFile = try AVAudioFile(
                    forWriting: audioURL,
                    settings: buffer.format.settings,
                    commonFormat: buffer.format.commonFormat,
                    interleaved: buffer.format.isInterleaved
                )
            }
            try audioFile?.write(from: buffer)
        } catch {
            writeError = error
        }
        stateLock.unlock()

        if let writeError {
            finishCompletion(.failure(writeError))
        }
    }

    func finish() {
        guard let runtimePath = runtimePath(),
              let selectedModel = selectedModel(localeIdentifier: activeLocaleIdentifier),
              let modelPath = selectedModel.storagePath,
              let audioURL
        else {
            let reason: String
            if runtimePath() == nil {
                reason = "Whisper runtime not found"
            } else if selectedModel(localeIdentifier: activeLocaleIdentifier) == nil {
                reason = "No Whisper model selected"
            } else if selectedModel(localeIdentifier: activeLocaleIdentifier)?.storagePath == nil {
                reason = "Model path not set"
            } else {
                reason = "Audio URL not available"
            }
            logger.error("Transcription finish: \(reason)")
            finishCompletion(
                .failure(NSError(domain: "Murmur.Transcription", code: 12, userInfo: [NSLocalizedDescriptionKey: "The local Whisper runtime is not ready: \(reason)"]))
            )
            return
        }

        logger.info("Transcription: audio=\(audioURL.lastPathComponent), model=\(modelPath)")

        stateLock.lock()
        audioFile = nil
        stateLock.unlock()

        let language = whisperLanguageCode(for: activeLocaleIdentifier, selectedModelIdentifier: selectedModel.modelIdentifier)
        latestTranscript = "Transcribing locally…"
        partialHandler?(latestTranscript)

        Task.detached(priority: .userInitiated) {
            do {
                let output = try self.runWhisper(
                    executablePath: runtimePath,
                    modelPath: modelPath,
                    audioPath: audioURL.path,
                    language: language
                )
                let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty {
                    throw NSError(
                        domain: "Murmur.Transcription",
                        code: 13,
                        userInfo: [NSLocalizedDescriptionKey: "whisper-cli produced no transcript."]
                    )
                }
                self.finishCompletion(.success(cleaned))
            } catch {
                self.finishCompletion(.failure(error))
            }
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    func cancel() {
        stateLock.lock()
        currentProcess?.terminate()
        currentProcess = nil
        audioFile = nil
        let audioURL = audioURL
        self.audioURL = nil
        latestTranscript = ""
        completion = nil
        partialHandler = nil
        stateLock.unlock()

        if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    private func runtimePath() -> String? {
        MainActor.assumeIsolated {
            modelManager.runtimes.first(where: { $0.kind == .whisperCPP && $0.installState == .installed })?.installPath
        }
    }

    private func selectedModel(localeIdentifier: String) -> ModelDescriptor? {
        MainActor.assumeIsolated {
            let preferred = modelManager.preferredWhisperModel(using: settingsStore.snapshot)
            if localeIdentifier.lowercased().hasPrefix("en") == false,
               let preferred,
               preferred.modelIdentifier?.contains(".en") == true {
                return modelManager.whisperModels().first { descriptor in
                    descriptor.status == .ready && (descriptor.modelIdentifier?.contains(".en") == false)
                } ?? preferred
            }
            return preferred
        }
    }

    private func whisperLanguageCode(for localeIdentifier: String, selectedModelIdentifier: String?) -> String {
        if selectedModelIdentifier?.contains(".en") == true {
            return "en"
        }
        let locale = Locale(identifier: localeIdentifier)
        if let code = locale.language.languageCode?.identifier, code.isEmpty == false {
            return code
        }
        return "auto"
    }

    private func runWhisper(
        executablePath: String,
        modelPath: String,
        audioPath: String,
        language: String
    ) throws -> String {
        let fileManager = FileManager.default
        let modelExists = fileManager.fileExists(atPath: modelPath)
        let audioExists = fileManager.fileExists(atPath: audioPath)

        logger.info("runWhisper: model=\(modelPath, privacy: .public) exists=\(modelExists), audio=\(audioPath, privacy: .public) exists=\(audioExists)")

        let arguments = [
            "-m", modelPath,
            "-f", audioPath,
            "-np",    // suppress non-transcript output lines
            "-nt",    // omit timestamp brackets from output
            "-fa",    // enable flash attention for accuracy
            "-t", String(max(ProcessInfo.processInfo.activeProcessorCount / 2, 1)),
            "-l", language,
        ]

        defer {
            stateLock.lock()
            currentProcess = nil
            stateLock.unlock()
        }

        do {
            let output = try CLIProcessRunner.run(
                executablePath: executablePath,
                arguments: arguments,
                timeout: 60,
                onProcess: { [weak self] process in
                    self?.stateLock.lock()
                    self?.currentProcess = process
                    self?.stateLock.unlock()
                }
            )

            // Remove backend initialization logs that might be appended to output
            // These log lines start with specific patterns and should be removed
            var result = output
            let logPatterns = [
                "load_backend:",
                "ggml_metal_device_init:",
                "ggml_metal_library_init:",
                "ggml_metal_rsets_init:",
                "ggml_blas_"
            ]

            for pattern in logPatterns {
                if let range = result.range(of: pattern) {
                    result = String(result[..<range.lowerBound])
                }
            }

            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                throw NSError(
                    domain: "Murmur.Transcription",
                    code: 15,
                    userInfo: [NSLocalizedDescriptionKey: "whisper-cli produced no transcript. Please try again."]
                )
            }
            return cleaned
        } catch {
            let errorDesc = error.localizedDescription
            logger.error("whisper-cli error: \(errorDesc, privacy: .public)")
            if errorDesc.contains("whisper-cli failed") {
                throw NSError(
                    domain: "Murmur.Transcription",
                    code: 14,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Whisper transcription failed. Verify the model file exists at \(modelPath) and try again."]
                )
            }
            throw error
        }
    }

    private func finishCompletion(_ result: Result<String, Error>) {
        stateLock.lock()
        let completion = self.completion
        self.completion = nil
        let partialHandler = self.partialHandler
        self.partialHandler = nil
        if case .success(let text) = result {
            latestTranscript = text
            partialHandler?(text)
        }
        stateLock.unlock()

        completion?(result)
    }
}

/// Apple Speech Recognition engine (built-in, no download required).
/// Marked @unchecked Sendable because all access is initiated by @MainActor-isolated DictationSessionManager.
/// SFSpeechRecognizer callbacks are serialized to the main thread internally.
/// All mutations (recognizer, request, recognitionTask, partialHandler, completion, latestTranscript) are serialized through DictationSessionManager's session lifecycle.
final class SpeechRecognizerTranscriptionEngine: @unchecked Sendable, TranscriptionEngine {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var partialHandler: ((String) -> Void)?
    private var completion: ((Result<String, Error>) -> Void)?
    private(set) var latestTranscript = ""
    private var didComplete = false

    func startTranscribing(
        localeIdentifier: String,
        partialHandler: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) throws {
        cancel()

        let locale = Locale(identifier: localeIdentifier)
        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let recognizer else {
            throw NSError(domain: "Murmur.Transcription", code: 1, userInfo: [NSLocalizedDescriptionKey: "No speech recognizer is available for \(localeIdentifier)."])
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw NSError(domain: "Murmur.Transcription", code: 2, userInfo: [NSLocalizedDescriptionKey: "On-device speech recognition is not available for \(localeIdentifier)."])
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        self.recognizer = recognizer
        self.request = request
        self.partialHandler = partialHandler
        self.completion = completion
        self.latestTranscript = ""
        self.didComplete = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.latestTranscript = text
                partialHandler(text)
                if result.isFinal {
                    self.finishCompletion(.success(text))
                }
            }
            if let error {
                self.finishCompletion(.failure(error))
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func finish() {
        request?.endAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, !self.didComplete else { return }
            if self.latestTranscript.isEmpty {
                self.finishCompletion(
                    .failure(NSError(domain: "Murmur.Transcription", code: 3, userInfo: [NSLocalizedDescriptionKey: "No speech was detected."]))
                )
            } else {
                self.finishCompletion(.success(self.latestTranscript))
            }
        }
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        recognizer = nil
        latestTranscript = ""
        didComplete = false
    }

    private func finishCompletion(_ result: Result<String, Error>) {
        guard !didComplete else { return }
        didComplete = true
        completion?(result)
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
    }
}

private extension Data {
    static func + (lhs: Data, rhs: Data) -> Data {
        var data = lhs
        data.append(rhs)
        return data
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
