import CryptoKit
import Foundation

enum WhisperModelLanguage: String, CaseIterable, Identifiable, Sendable {
    case english
    case multilingual

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum WhisperModelSpeed: String, Sendable {
    case fastest = "Fastest"
    case fast = "Fast"
    case balanced = "Balanced"
    case slower = "Slower"
}

struct WhisperDownloadManifest: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let fileName: String
    let byteCount: Int64
    let sha256: String
    let downloadURL: URL
    let language: WhisperModelLanguage
    let speed: WhisperModelSpeed
    let quality: String
    let qualityDescription: String
    let isRecommended: Bool

    static let tinyEnglish = WhisperDownloadManifest(
        id: "tiny.en",
        displayName: "Tiny English",
        fileName: "ggml-tiny.en.bin",
        byteCount: 77_704_715,
        sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f",
        downloadURL: modelURL(fileName: "ggml-tiny.en.bin"),
        language: .english,
        speed: .fastest,
        quality: "Basic",
        qualityDescription: "The quickest English model for short, clear dictation.",
        isRecommended: false
    )

    static let baseEnglish = WhisperDownloadManifest(
        id: "base.en",
        displayName: "Base English",
        fileName: "ggml-base.en.bin",
        byteCount: 147_964_211,
        sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
        downloadURL: modelURL(fileName: "ggml-base.en.bin"),
        language: .english,
        speed: .fast,
        quality: "Good",
        qualityDescription: "A light English model with better accuracy than Tiny.",
        isRecommended: false
    )

    static let smallEnglish = WhisperDownloadManifest(
        id: "small.en",
        displayName: "Small English",
        fileName: "ggml-small.en.bin",
        byteCount: 487_614_201,
        sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d",
        downloadURL: modelURL(fileName: "ggml-small.en.bin"),
        language: .english,
        speed: .balanced,
        quality: "High",
        qualityDescription: "The best balance of whisper accuracy and speed for English dictation.",
        isRecommended: true
    )

    static let tinyMultilingual = WhisperDownloadManifest(
        id: "tiny",
        displayName: "Tiny Multilingual",
        fileName: "ggml-tiny.bin",
        byteCount: 77_691_713,
        sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
        downloadURL: modelURL(fileName: "ggml-tiny.bin"),
        language: .multilingual,
        speed: .fastest,
        quality: "Basic",
        qualityDescription: "The smallest multilingual option for clear speech.",
        isRecommended: false
    )

    static let baseMultilingual = WhisperDownloadManifest(
        id: "base",
        displayName: "Base Multilingual",
        fileName: "ggml-base.bin",
        byteCount: 147_951_465,
        sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
        downloadURL: modelURL(fileName: "ggml-base.bin"),
        language: .multilingual,
        speed: .fast,
        quality: "Good",
        qualityDescription: "A compact multilingual model for everyday speech.",
        isRecommended: false
    )

    static let smallMultilingual = WhisperDownloadManifest(
        id: "small",
        displayName: "Small Multilingual",
        fileName: "ggml-small.bin",
        byteCount: 487_601_967,
        sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
        downloadURL: modelURL(fileName: "ggml-small.bin"),
        language: .multilingual,
        speed: .balanced,
        quality: "High",
        qualityDescription: "A balanced multilingual model for quieter or more varied speech.",
        isRecommended: false
    )

    static let largeV3TurboQ5 = WhisperDownloadManifest(
        id: "large-v3-turbo-q5_0",
        displayName: "Large v3 Turbo Compact",
        fileName: "ggml-large-v3-turbo-q5_0.bin",
        byteCount: 574_041_195,
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
        downloadURL: modelURL(fileName: "ggml-large-v3-turbo-q5_0.bin"),
        language: .multilingual,
        speed: .balanced,
        quality: "Very high",
        qualityDescription: "Near-Large quality with a much smaller local footprint.",
        isRecommended: false
    )

    static let largeV3Turbo = WhisperDownloadManifest(
        id: "large-v3-turbo",
        displayName: "Large v3 Turbo",
        fileName: "ggml-large-v3-turbo.bin",
        byteCount: 1_624_555_275,
        sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
        downloadURL: modelURL(fileName: "ggml-large-v3-turbo.bin"),
        language: .multilingual,
        speed: .slower,
        quality: "Highest",
        qualityDescription: "The most accurate option, with the largest download and slowest response.",
        isRecommended: false
    )

    static let supported = [
        tinyEnglish,
        baseEnglish,
        smallEnglish,
        tinyMultilingual,
        baseMultilingual,
        smallMultilingual,
        largeV3TurboQ5,
        largeV3Turbo,
    ]

    private static func modelURL(fileName: String) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }
}

enum WhisperModelSelectionPolicy {
    static let recommendedIdentifier = WhisperDownloadManifest.smallEnglish.id

    private static let fallbackOrder = [
        WhisperDownloadManifest.smallEnglish.id,
        WhisperDownloadManifest.baseEnglish.id,
        WhisperDownloadManifest.largeV3TurboQ5.id,
        WhisperDownloadManifest.largeV3Turbo.id,
        WhisperDownloadManifest.smallMultilingual.id,
        WhisperDownloadManifest.baseMultilingual.id,
        WhisperDownloadManifest.tinyEnglish.id,
        WhisperDownloadManifest.tinyMultilingual.id,
    ]

    static func fallback(
        afterRemoving removedIdentifier: String,
        installedIdentifiers: Set<String>
    ) -> String? {
        let remaining = installedIdentifiers.subtracting([removedIdentifier])
        return fallbackOrder.first(where: remaining.contains) ?? remaining.sorted().first
    }
}

enum ModelInstallError: Error, LocalizedError {
    case invalidResponse
    case checksumMismatch
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The model server returned an invalid response."
        case .checksumMismatch: "The downloaded model failed its integrity check and was not installed."
        case .cancelled: "The model download was cancelled."
        }
    }
}

enum WhisperModelManagementError: Error, LocalizedError {
    case downloadInProgress

    var errorDescription: String? {
        switch self {
        case .downloadInProgress:
            "Cancel the model download before deleting it."
        }
    }
}

enum ModelIntegrityVerifier {
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), data.isEmpty == false {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verify(url: URL, expectedSHA256: String) throws -> Bool {
        try sha256(of: url).caseInsensitiveCompare(expectedSHA256) == .orderedSame
    }
}

enum ModelFileActivator {
    static func activate(stagedURL: URL, destinationURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagedURL)
        } else {
            try fileManager.moveItem(at: stagedURL, to: destinationURL)
        }
    }
}

final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var stagingURL: URL?
    private var progressHandler: (@Sendable (Int64, Int64, Double) -> Void)?
    private var completedDownload = false
    private var task: URLSessionDownloadTask?
    private var startedAt = Date()

    func download(
        from remoteURL: URL,
        stagingURL: URL,
        resumeData: Data? = nil,
        progressHandler: @escaping @Sendable (Int64, Int64, Double) -> Void
    ) async throws -> URL {
        self.stagingURL = stagingURL
        self.progressHandler = progressHandler
        completedDownload = false
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
                self.session = session
                let task = resumeData.map(session.downloadTask(withResumeData:)) ?? session.downloadTask(with: remoteURL)
                self.task = task
                self.startedAt = Date()
                task.resume()
                lock.unlock()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func pause(completion: @escaping @Sendable (Data?) -> Void) {
        lock.lock()
        let task = task
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        task?.cancel { data in
            completion(data)
            continuation?.resume(throwing: ModelInstallError.cancelled)
        }
    }

    func cancel() {
        lock.lock()
        session?.invalidateAndCancel()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: ModelInstallError.cancelled)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let elapsed = max(Date().timeIntervalSince(startedAt), 0.1)
        progressHandler?(totalBytesWritten, totalBytesExpectedToWrite, Double(totalBytesWritten) / elapsed)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        guard let stagingURL else {
            lock.unlock()
            return
        }
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200...299).contains(response.statusCode),
              response.url?.scheme?.lowercased() == "https"
        else {
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            session.invalidateAndCancel()
            continuation?.resume(throwing: ModelInstallError.invalidResponse)
            return
        }
        do {
            try? FileManager.default.removeItem(at: stagingURL)
            try FileManager.default.moveItem(at: location, to: stagingURL)
            completedDownload = true
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            session.finishTasksAndInvalidate()
            continuation?.resume(returning: stagingURL)
        } catch {
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            session.invalidateAndCancel()
            continuation?.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        lock.lock()
        guard completedDownload == false else {
            lock.unlock()
            return
        }
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

@MainActor
final class WhisperModelInstaller: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(WhisperDownloadManifest)
        case paused(WhisperDownloadManifest)
        case verifying(WhisperDownloadManifest)
        case installed(WhisperDownloadManifest)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var progress = 0.0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var expectedBytes: Int64 = 0
    @Published private(set) var bytesPerSecond: Double = 0

    private var delegate: ModelDownloadDelegate?
    private var installTask: Task<Void, Never>?
    private var isPausing = false
    private var activeManifest: WhisperDownloadManifest?

    private var resumeDataURL: URL {
        MurmurV2Paths.modelsDirectory.appendingPathComponent("Whisper/download.resume")
    }
    private var resumeManifestURL: URL {
        MurmurV2Paths.modelsDirectory.appendingPathComponent("Whisper/download-manifest.txt")
    }

    init() {
        guard let identifier = try? String(contentsOf: resumeManifestURL, encoding: .utf8),
              let manifest = WhisperDownloadManifest.supported.first(where: { $0.id == identifier }),
              FileManager.default.fileExists(atPath: resumeDataURL.path)
        else { return }
        activeManifest = manifest
        expectedBytes = manifest.byteCount
        state = .paused(manifest)
    }

    func install(_ manifest: WhisperDownloadManifest) {
        cancel(removePartial: true)
        downloadedBytes = 0
        expectedBytes = manifest.byteCount
        bytesPerSecond = 0
        progress = 0
        install(manifest, preservingResumeData: false)
    }

    func pause() {
        guard case .downloading(let manifest) = state else { return }
        isPausing = true
        delegate?.pause { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                if let data {
                    try? FileManager.default.createDirectory(at: self.resumeDataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: self.resumeDataURL, options: .atomic)
                    try? manifest.id.write(to: self.resumeManifestURL, atomically: true, encoding: .utf8)
                    self.state = .paused(manifest)
                } else {
                    self.state = .failed("This server could not pause the download. Try again.")
                }
                self.isPausing = false
                self.installTask = nil
                self.delegate = nil
            }
        }
    }

    func resume() {
        guard case .paused(let manifest) = state else { return }
        install(manifest, preservingResumeData: true)
    }

    private func install(_ manifest: WhisperDownloadManifest, preservingResumeData: Bool) {
        if preservingResumeData == false { clearResumeState() }
        progress = expectedBytes > 0 ? Double(downloadedBytes) / Double(expectedBytes) : 0
        state = .downloading(manifest)
        activeManifest = manifest
        let delegate = ModelDownloadDelegate()
        self.delegate = delegate
        installTask = makeInstallTask(manifest: manifest, delegate: delegate)
    }

    private func makeInstallTask(manifest: WhisperDownloadManifest, delegate: ModelDownloadDelegate) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let directory = MurmurV2Paths.modelsDirectory.appendingPathComponent("Whisper", isDirectory: true)
            let stagingURL = directory.appendingPathComponent("\(manifest.fileName).partial")
            let destinationURL = directory.appendingPathComponent(manifest.fileName)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let resumeData = try? Data(contentsOf: resumeDataURL)
                let downloadedURL = try await delegate.download(from: manifest.downloadURL, stagingURL: stagingURL, resumeData: resumeData) { downloaded, expected, speed in
                    Task { @MainActor [weak self] in
                        self?.downloadedBytes = downloaded; self?.expectedBytes = expected; self?.bytesPerSecond = speed
                        self?.progress = expected > 0 ? Double(downloaded) / Double(expected) : 0
                    }
                }
                state = .verifying(manifest)
                guard try ModelIntegrityVerifier.verify(url: downloadedURL, expectedSHA256: manifest.sha256) else { throw ModelInstallError.checksumMismatch }
                try ModelFileActivator.activate(stagedURL: downloadedURL, destinationURL: destinationURL)
                await LocalWhisperModelVerificationCache.shared.invalidate()
                progress = 1; state = .installed(manifest); clearResumeState()
            } catch ModelInstallError.cancelled { if isPausing == false { state = .idle } }
            catch { if isPausing == false { state = .failed(error.localizedDescription) } }
        }
    }

    func cancel(removePartial: Bool = true) {
        installTask?.cancel()
        delegate?.cancel()
        installTask = nil
        delegate = nil
        if removePartial {
            clearResumeState()
            if let activeManifest {
                let partial = MurmurV2Paths.modelsDirectory.appendingPathComponent("Whisper/\(activeManifest.fileName).partial")
                try? FileManager.default.removeItem(at: partial)
            }
        }
        if case .downloading = state { state = .idle }
        if case .paused = state { state = .idle }
    }

    private func clearResumeState() {
        try? FileManager.default.removeItem(at: resumeDataURL)
        try? FileManager.default.removeItem(at: resumeManifestURL)
    }
}
