import CryptoKit
import Foundation

struct LocalWhisperModel: Identifiable, Equatable, Sendable {
    let identifier: String
    let fileURL: URL
    let byteCount: Int64
    let sha256: String

    var id: String { identifier }
}

struct LocalTranscriptionRequest: Sendable {
    let audioFileURL: URL
    let model: LocalWhisperModel
    let language: String
    let prompt: String?
    let beamSize: Int
    let bestOf: Int
    let quietSpeechLikely: Bool

    init(
        audioFileURL: URL,
        model: LocalWhisperModel,
        language: String,
        prompt: String?,
        beamSize: Int,
        bestOf: Int,
        quietSpeechLikely: Bool = false
    ) {
        self.audioFileURL = audioFileURL
        self.model = model
        self.language = language
        self.prompt = prompt
        self.beamSize = beamSize
        self.bestOf = bestOf
        self.quietSpeechLikely = quietSpeechLikely
    }
}

struct LocalTranscriptionResult: Equatable, Sendable {
    let text: String
    let usedBeamSize: Int
    let elapsed: Duration
}

enum LocalTranscriptionError: Error, LocalizedError {
    case runtimeUnavailable
    case modelUnavailable
    case emptyTranscript
    case processFailed(exitCode: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable: "The bundled local Whisper runtime is unavailable."
        case .modelUnavailable: "No verified local Whisper model is installed."
        case .emptyTranscript: "Murmur could not hear enough speech to transcribe safely."
        case .processFailed(let exitCode, let message):
            "Local transcription failed (\(exitCode)): \(message)"
        }
    }
}

protocol LocalTranscriptionEngine: Sendable {
    func transcribe(_ request: LocalTranscriptionRequest) async throws -> LocalTranscriptionResult
    func cancel() async
}

enum WaveFileEncoder {
    static func encode(samples: [Float], sampleRate: UInt32 = 16_000) throws -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataByteCount = UInt32(clamping: samples.count) * bytesPerSample
        var data = Data()
        data.reserveCapacity(44 + Int(dataByteCount))

        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36) + dataByteCount)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channelCount)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(sampleRate * UInt32(channelCount) * bytesPerSample)
        data.appendLittleEndian(channelCount * UInt16(bytesPerSample))
        data.appendLittleEndian(bitsPerSample)
        data.appendASCII("data")
        data.appendLittleEndian(dataByteCount)

        for sample in samples {
            let clamped = min(max(sample, -1), 1)
            let integer = Int16(clamping: Int((clamped * Float(Int16.max)).rounded()))
            data.appendLittleEndian(UInt16(bitPattern: integer))
        }
        return data
    }

    static func writeTemporaryFile(samples: [Float], sampleRate: UInt32 = 16_000) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-\(UUID().uuidString).wav")
        try encode(samples: samples, sampleRate: sampleRate).write(to: url, options: [.atomic])
        return url
    }
}

struct LocalWhisperModelCatalog: Sendable {
    let directory: URL

    init(directory: URL = MurmurV2Paths.modelsDirectory.appendingPathComponent("Whisper", isDirectory: true)) {
        self.directory = directory
    }

    func installedModels(verifyIntegrity: Bool = false) throws -> [LocalWhisperModel] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix("ggml-"), url.pathExtension == "bin" else { return nil }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            let identifier = url.deletingPathExtension().lastPathComponent.dropFirst("ggml-".count)
            let identifierString = String(identifier)
            let expectedDigest = WhisperDownloadManifest.supported
                .first(where: { $0.id == identifierString })?.sha256 ?? ""
            let digest = verifyIntegrity ? try Self.sha256(of: url) : expectedDigest
            return LocalWhisperModel(
                identifier: identifierString,
                fileURL: url,
                byteCount: Int64(values.fileSize ?? 0),
                sha256: digest
            )
        }
        .sorted { $0.identifier < $1.identifier }
    }

    func removeModel(identifier: String) throws {
        let allowed = identifier.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0)
        }
        guard allowed, identifier.isEmpty == false, identifier.count <= 100 else {
            throw LocalTranscriptionError.modelUnavailable
        }
        let url = directory.appendingPathComponent("ggml-\(identifier).bin")
        let canonicalDirectory = directory.standardizedFileURL.path
        let canonicalURL = url.standardizedFileURL.path
        guard canonicalURL.hasPrefix(canonicalDirectory + "/") else {
            throw LocalTranscriptionError.modelUnavailable
        }
        if FileManager.default.fileExists(atPath: canonicalURL) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), chunk.isEmpty == false {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

actor LocalWhisperModelVerificationCache {
    static let shared = LocalWhisperModelVerificationCache()
    private var modelsByDirectory: [String: [LocalWhisperModel]] = [:]

    func verifiedModels(in catalog: LocalWhisperModelCatalog) throws -> [LocalWhisperModel] {
        let key = catalog.directory.standardizedFileURL.path
        if let cached = modelsByDirectory[key] { return cached }
        let discovered = try catalog.installedModels(verifyIntegrity: true)
        let verified = discovered.filter { model in
            guard let manifest = WhisperDownloadManifest.supported.first(where: { $0.id == model.identifier }) else {
                return true
            }
            return model.sha256.caseInsensitiveCompare(manifest.sha256) == .orderedSame
        }
        modelsByDirectory[key] = verified
        return verified
    }

    func invalidate() {
        modelsByDirectory.removeAll()
    }
}

struct WhisperRuntimeLocation: Equatable, Sendable {
    let executableURL: URL
    let backendDirectory: URL
}

struct WhisperRuntimeProcessConfiguration: Equatable, Sendable {
    let environment: [String: String]
    let currentDirectoryURL: URL

    init(
        runtime: WhisperRuntimeLocation,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        var environment = inheritedEnvironment
        environment.removeValue(forKey: "GGML_BACKEND_PATH")
        self.environment = environment
        currentDirectoryURL = runtime.backendDirectory
    }
}

enum WhisperRuntimeResolver {
    static func resolve(bundle: Bundle = .main) -> WhisperRuntimeLocation? {
        var candidates: [URL] = []
        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Runtimes/arm64", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("Vendor/Runtimes/arm64", isDirectory: true))
        }

#if DEBUG
        var projectRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { projectRoot.deleteLastPathComponent() }
        candidates.append(projectRoot.appendingPathComponent("Vendor/Runtimes/arm64", isDirectory: true))
#endif

        let locations: [WhisperRuntimeLocation] = candidates.compactMap { root in
            let executable = root.appendingPathComponent("whisper-cli")
            let backendDirectory = root.appendingPathComponent("libexec", isDirectory: true)
            guard FileManager.default.isExecutableFile(atPath: executable.path),
                  FileManager.default.fileExists(atPath: backendDirectory.path)
            else { return nil }
            return WhisperRuntimeLocation(executableURL: executable, backendDirectory: backendDirectory)
        }
        return locations.first
    }
}

enum WhisperOutputParser {
    static func parse(_ output: String) -> String {
        let ignoredPrefixes = [
            "ggml_", "whisper_", "main:", "system_info:", "metal_", "load_",
        ]
        let ignoredTokens: Set<String> = [
            "[blank_audio]", "blank_audio", "[silence]", "[music]",
        ]
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                let lowercased = line.lowercased()
                return line.isEmpty == false
                    && ignoredPrefixes.contains(where: lowercased.hasPrefix) == false
                    && ignoredTokens.contains(lowercased) == false
            }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor WhisperCLITranscriptionEngine: LocalTranscriptionEngine {
    private var activeExecution: WhisperProcessExecution?

    func transcribe(_ request: LocalTranscriptionRequest) async throws -> LocalTranscriptionResult {
        guard FileManager.default.fileExists(atPath: request.model.fileURL.path) else {
            throw LocalTranscriptionError.modelUnavailable
        }
        guard let runtime = WhisperRuntimeResolver.resolve() else {
            throw LocalTranscriptionError.runtimeUnavailable
        }

        let clock = ContinuousClock()
        let startedAt = clock.now
        let primary = try await runPass(
            request: request,
            runtime: runtime,
            beamSize: max(request.beamSize, 1),
            bestOf: max(request.bestOf, 1),
            noSpeechThreshold: request.quietSpeechLikely ? 0.82 : 0.72,
            logProbabilityThreshold: -1.15
        )
        var selected = primary
        var selectedBeamSize = request.beamSize

        if request.quietSpeechLikely || TranscriptQualityEvaluator.shouldRetry(primary) {
            do {
                let sensitive = try await runPass(
                    request: request,
                    runtime: runtime,
                    beamSize: max(request.beamSize, 8),
                    bestOf: max(request.bestOf, 8),
                    noSpeechThreshold: 0.90,
                    logProbabilityThreshold: -1.45
                )
                if TranscriptQualityEvaluator.score(sensitive) > TranscriptQualityEvaluator.score(primary) {
                    selected = sensitive
                    selectedBeamSize = max(request.beamSize, 8)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The verified primary pass remains safer than failing the entire session.
            }
        }

        guard selected.isEmpty == false else { throw LocalTranscriptionError.emptyTranscript }
        return LocalTranscriptionResult(
            text: selected,
            usedBeamSize: selectedBeamSize,
            elapsed: startedAt.duration(to: clock.now)
        )
    }

    func cancel() {
        activeExecution?.cancel()
        activeExecution = nil
    }

    private func runPass(
        request: LocalTranscriptionRequest,
        runtime: WhisperRuntimeLocation,
        beamSize: Int,
        bestOf: Int,
        noSpeechThreshold: Double,
        logProbabilityThreshold: Double
    ) async throws -> String {
        let processConfiguration = WhisperRuntimeProcessConfiguration(runtime: runtime)
        let execution = try WhisperProcessExecution(
            executableURL: runtime.executableURL,
            configuration: processConfiguration,
            arguments: arguments(
                request: request,
                beamSize: beamSize,
                bestOf: bestOf,
                noSpeechThreshold: noSpeechThreshold,
                logProbabilityThreshold: logProbabilityThreshold
            )
        )
        activeExecution = execution
        defer {
            if activeExecution === execution { activeExecution = nil }
        }
        let output = try await Task.detached(priority: .userInitiated) {
            try execution.run()
        }.value
        try Task.checkCancellation()
        return WhisperOutputParser.parse(output)
    }

    private func arguments(
        request: LocalTranscriptionRequest,
        beamSize: Int,
        bestOf: Int,
        noSpeechThreshold: Double,
        logProbabilityThreshold: Double
    ) -> [String] {
        var arguments = [
            "-m", request.model.fileURL.path,
            "-f", request.audioFileURL.path,
            "-np", "-nt", "-fa", "-sns",
            "-l", request.language,
            "-bs", String(beamSize),
            "-bo", String(bestOf),
            "-t", String(max(ProcessInfo.processInfo.activeProcessorCount / 2, 2)),
            "-nth", String(format: "%.2f", noSpeechThreshold),
            "-lpt", String(format: "%.2f", logProbabilityThreshold),
        ]
        if let prompt = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), prompt.isEmpty == false {
            arguments.append(contentsOf: ["--prompt", String(prompt.prefix(2_000))])
        }
        return arguments
    }
}

enum TranscriptQualityEvaluator {
    static func shouldRetry(_ text: String) -> Bool {
        let words = normalizedWords(text)
        guard words.isEmpty == false else { return true }
        if text.contains("[") || text.contains("]") { return true }
        if repeatedRunPenalty(words) >= 2 { return true }
        return words.count <= 2
    }

    static func score(_ text: String) -> Double {
        let words = normalizedWords(text)
        guard words.isEmpty == false else { return -.infinity }
        let substantiveCharacters = text.filter { $0.isLetter || $0.isNumber }.count
        let repetitionPenalty = repeatedRunPenalty(words) * 4
        let artifactPenalty = (text.contains("[") || text.contains("]")) ? 20 : 0
        return Double(substantiveCharacters + min(words.count, 40) - repetitionPenalty - artifactPenalty)
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { $0.isLetter == false && $0.isNumber == false }).map(String.init)
    }

    private static func repeatedRunPenalty(_ words: [String]) -> Int {
        guard words.count > 1 else { return 0 }
        return zip(words, words.dropFirst()).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
    }
}

enum WhisperProcessTermination: Equatable, Sendable {
    case succeeded
    case cancelled
    case failed(exitCode: Int32, message: String)

    static func classify(
        reason: Process.TerminationReason,
        status: Int32,
        standardError: String,
        cancellationRequested: Bool
    ) -> WhisperProcessTermination {
        if reason == .exit, status == 0 { return .succeeded }
        if cancellationRequested { return .cancelled }

        let capturedMessage = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if capturedMessage.isEmpty == false {
            message = String(capturedMessage.suffix(2_000))
        } else if reason == .uncaughtSignal {
            message = "The local transcription runtime crashed with signal \(status)."
        } else {
            message = "The local transcription runtime stopped unexpectedly."
        }
        return .failed(exitCode: status, message: message)
    }
}

private final class WhisperProcessExecution: @unchecked Sendable {
    private let process: Process
    private let standardOutputURL: URL
    private let standardErrorURL: URL
    private let standardOutputHandle: FileHandle
    private let standardErrorHandle: FileHandle
    private let stateLock = NSLock()
    private var cancellationRequested = false

    init(
        executableURL: URL,
        configuration: WhisperRuntimeProcessConfiguration,
        arguments: [String]
    ) throws {
        let directory = FileManager.default.temporaryDirectory
        standardOutputURL = directory.appendingPathComponent("murmur-whisper-\(UUID().uuidString).out")
        standardErrorURL = directory.appendingPathComponent("murmur-whisper-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: standardOutputURL.path, contents: nil)
        FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)
        standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
        standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
        process = Process()
        process.executableURL = executableURL
        process.environment = configuration.environment
        process.currentDirectoryURL = configuration.currentDirectoryURL
        process.arguments = arguments
        process.standardOutput = standardOutputHandle
        process.standardError = standardErrorHandle
    }

    func run() throws -> String {
        defer {
            try? standardOutputHandle.close()
            try? standardErrorHandle.close()
            try? FileManager.default.removeItem(at: standardOutputURL)
            try? FileManager.default.removeItem(at: standardErrorURL)
        }
        if wasCancellationRequested() { throw CancellationError() }
        try process.run()
        if wasCancellationRequested(), process.isRunning { process.terminate() }
        process.waitUntilExit()
        try standardOutputHandle.synchronize()
        try standardErrorHandle.synchronize()
        let outputData = try Data(contentsOf: standardOutputURL)
        let errorData = try Data(contentsOf: standardErrorURL)

        let termination = WhisperProcessTermination.classify(
            reason: process.terminationReason,
            status: process.terminationStatus,
            standardError: String(data: errorData, encoding: .utf8) ?? "",
            cancellationRequested: wasCancellationRequested()
        )
        switch termination {
        case .succeeded:
            return String(data: outputData, encoding: .utf8) ?? ""
        case .cancelled:
            throw CancellationError()
        case .failed(let exitCode, let message):
            throw LocalTranscriptionError.processFailed(exitCode: exitCode, message: message)
        }
    }

    func cancel() {
        stateLock.lock()
        cancellationRequested = true
        let isRunning = process.isRunning
        stateLock.unlock()
        if isRunning { process.terminate() }
    }

    private func wasCancellationRequested() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancellationRequested
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
