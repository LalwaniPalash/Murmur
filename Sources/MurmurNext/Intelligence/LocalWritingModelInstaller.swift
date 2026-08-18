import Foundation

struct LocalWritingModelDownloadRequest: Equatable, Sendable {
    let repository: String
    let revision: String
    let requiredPaths: [String]
    let destination: URL
}

protocol LocalWritingModelSnapshotDownloading: Sendable {
    func download(_ request: LocalWritingModelDownloadRequest) async throws -> URL
}

enum LocalWritingModelInstallFailure: Error, Equatable, LocalizedError, Sendable {
    case unsupportedModel
    case cancelled
    case downloadFailed
    case unsafeDownloadLocation
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedModel: "That local writing model is not supported."
        case .cancelled: "The local writing model download was cancelled."
        case .downloadFailed: "The local writing model could not be downloaded."
        case .unsafeDownloadLocation: "The local writing model was downloaded to an unsafe location."
        case .verificationFailed: "The local writing model failed its integrity check."
        }
    }
}

actor LocalWritingModelInstaller {
    private let catalog: LocalWritingModelCatalog
    private let downloader: any LocalWritingModelSnapshotDownloading

    init(
        catalog: LocalWritingModelCatalog = LocalWritingModelCatalog(),
        downloader: any LocalWritingModelSnapshotDownloading = HuggingFaceLocalWritingModelDownloader()
    ) {
        self.catalog = catalog
        self.downloader = downloader
    }

    /// Installation begins only when the caller explicitly invokes this method.
    /// Loading and generation never call the downloader.
    func install(identifier: String) async throws -> URL {
        guard let manifest = catalog.manifest(identifier: identifier) else {
            throw LocalWritingModelInstallFailure.unsupportedModel
        }
        try Task.checkCancellation()
        do {
            try FileManager.default.createDirectory(
                at: catalog.rootDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw LocalWritingModelInstallFailure.downloadFailed
        }

        let staging = catalog.rootDirectory
            .appendingPathComponent(".installing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let downloaded: URL
        do {
            downloaded = try await downloader.download(
                LocalWritingModelDownloadRequest(
                    repository: manifest.repository,
                    revision: manifest.revision,
                    requiredPaths: manifest.files.map(\.relativePath),
                    destination: staging
                )
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw LocalWritingModelInstallFailure.cancelled
        } catch {
            throw LocalWritingModelInstallFailure.downloadFailed
        }

        guard downloaded.standardizedFileURL == staging.standardizedFileURL else {
            throw LocalWritingModelInstallFailure.unsafeDownloadLocation
        }
        do {
            return try catalog.activate(manifest, stagedDirectory: staging)
        } catch {
            throw LocalWritingModelInstallFailure.verificationFailed
        }
    }

    /// Removal is explicit and limited to the verified install directory for a catalog model.
    func remove(identifier: String) throws {
        guard let manifest = catalog.manifest(identifier: identifier) else {
            throw LocalWritingModelInstallFailure.unsupportedModel
        }
        let directory: URL
        do {
            directory = try catalog.verifiedModelDirectory(identifier: identifier)
        } catch LocalWritingModelCatalogError.modelUnavailable {
            return
        } catch {
            throw LocalWritingModelInstallFailure.verificationFailed
        }
        guard directory == catalog.installDirectory(for: manifest) else {
            throw LocalWritingModelInstallFailure.verificationFailed
        }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw LocalWritingModelInstallFailure.verificationFailed
        }
    }
}
