import Foundation

@MainActor
final class LocalWritingModelTransfer: ObservableObject {
    enum State: Equatable { case idle, downloading, paused, verifying, installed, failed(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var progress = 0.0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var expectedBytes: Int64
    @Published private(set) var bytesPerSecond = 0.0
    @Published private(set) var manifest: LocalWritingModelManifest

    private let catalog = LocalWritingModelCatalog()
    private var delegate: ModelDownloadDelegate?
    private var task: Task<Void, Never>?
    private var isPausing = false
    private var currentIndex = 0

    private var transferKey: String { catalog.installDirectory(for: manifest).lastPathComponent }
    private var stagingURL: URL { catalog.rootDirectory.appendingPathComponent(".writing-transfer-\(transferKey)", isDirectory: true) }
    private var resumeURL: URL { catalog.rootDirectory.appendingPathComponent(".writing-transfer-\(transferKey).resume") }
    private var stateURL: URL { catalog.rootDirectory.appendingPathComponent(".writing-transfer-\(transferKey).state") }

    init(manifest: LocalWritingModelManifest = .qwen3_0_6B_4Bit) {
        self.manifest = manifest
        expectedBytes = manifest.byteCount
        restoreState()
    }

    func select(_ selected: LocalWritingModelManifest) {
        guard selected.id != manifest.id, state != .downloading, state != .verifying else { return }
        manifest = selected
        expectedBytes = selected.byteCount
        currentIndex = 0
        downloadedBytes = 0
        progress = 0
        bytesPerSecond = 0
        state = .idle
        restoreState()
    }

    func install(_ selected: LocalWritingModelManifest) {
        select(selected)
        install()
    }

    private func restoreState() {
        if let value = try? String(contentsOf: stateURL, encoding: .utf8),
           let index = Int(value), manifest.files.indices.contains(index) {
            currentIndex = index
            downloadedBytes = completedByteCount(before: index)
            progress = Double(downloadedBytes) / Double(expectedBytes)
            state = .paused
        } else if (try? catalog.verifiedModelDirectory(identifier: manifest.id)) != nil {
            downloadedBytes = expectedBytes
            progress = 1
            state = .installed
        }
    }

    func install() {
        cancel()
        currentIndex = 0
        downloadedBytes = 0
        progress = 0
        start(preservingResume: false)
    }

    func resume() {
        guard state == .paused else { return }
        start(preservingResume: true)
    }

    func pause() {
        guard state == .downloading else { return }
        isPausing = true
        delegate?.pause { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                if let data {
                    try? data.write(to: self.resumeURL, options: .atomic)
                    try? String(self.currentIndex).write(to: self.stateURL, atomically: true, encoding: .utf8)
                    self.state = .paused
                } else {
                    self.state = .failed("This server could not pause the download. Try again.")
                }
                self.isPausing = false
                self.delegate = nil
                self.task = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        delegate?.cancel()
        task = nil
        delegate = nil
        try? FileManager.default.removeItem(at: stagingURL)
        try? FileManager.default.removeItem(at: resumeURL)
        try? FileManager.default.removeItem(at: stateURL)
        if state != .installed { state = .idle }
    }

    func remove() throws {
        cancel()
        try catalog.removeVerifiedModel(manifest)
        downloadedBytes = 0
        progress = 0
        state = .idle
    }

    private func start(preservingResume: Bool) {
        if preservingResume == false {
            try? FileManager.default.removeItem(at: resumeURL)
            try? FileManager.default.removeItem(at: stateURL)
        }
        state = .downloading
        task = Task { @MainActor [weak self] in await self?.run() }
    }

    private func run() async {
        do {
            try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
            for index in currentIndex..<manifest.files.count {
                currentIndex = index
                let file = manifest.files[index]
                let destination = stagingURL.appendingPathComponent(file.relativePath)
                if FileManager.default.fileExists(atPath: destination.path),
                   (try? ModelIntegrityVerifier.verify(url: destination, expectedSHA256: file.sha256)) == true {
                    downloadedBytes = completedByteCount(before: index + 1)
                    continue
                }
                let delegate = ModelDownloadDelegate()
                self.delegate = delegate
                let remote = URL(string: "https://huggingface.co/\(manifest.repository)/resolve/\(manifest.revision)/\(file.relativePath)")!
                let resumeData = index == currentIndex ? try? Data(contentsOf: resumeURL) : nil
                _ = try await delegate.download(from: remote, stagingURL: destination, resumeData: resumeData) { [weak self] current, _, speed in
                    Task { @MainActor in
                        guard let self else { return }
                        self.downloadedBytes = self.completedByteCount(before: index) + current
                        self.progress = min(Double(self.downloadedBytes) / Double(self.expectedBytes), 1)
                        self.bytesPerSecond = speed
                    }
                }
                try? FileManager.default.removeItem(at: resumeURL)
                downloadedBytes = completedByteCount(before: index + 1)
            }
            state = .verifying
            _ = try catalog.activate(manifest, stagedDirectory: stagingURL)
            try? FileManager.default.removeItem(at: stateURL)
            downloadedBytes = expectedBytes
            progress = 1
            state = .installed
        } catch ModelInstallError.cancelled {
            if isPausing == false { state = .idle }
        } catch is CancellationError {
            if isPausing == false { state = .idle }
        } catch {
            if isPausing == false { state = .failed(error.localizedDescription) }
        }
    }

    private func completedByteCount(before index: Int) -> Int64 {
        manifest.files.prefix(index).reduce(0) { $0 + $1.byteCount }
    }
}

private extension LocalWritingModelCatalog {
    func removeVerifiedModel(_ manifest: LocalWritingModelManifest) throws {
        let directory = try verifiedModelDirectory(identifier: manifest.id)
        try FileManager.default.removeItem(at: directory)
    }
}
