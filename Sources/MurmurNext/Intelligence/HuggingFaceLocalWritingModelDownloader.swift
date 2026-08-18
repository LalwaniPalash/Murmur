import Foundation
import HuggingFace

struct HuggingFaceLocalWritingModelDownloader: LocalWritingModelSnapshotDownloading, Sendable {
    private let client: HubClient

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1_800
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        client = HubClient(
            session: URLSession(configuration: configuration),
            host: HubClient.defaultHost,
            userAgent: "Murmur/2 local-writing-model-installer",
            bearerToken: nil,
            cache: nil
        )
    }

    func download(_ request: LocalWritingModelDownloadRequest) async throws -> URL {
        guard let repository = Repo.ID(rawValue: request.repository),
              request.revision.count == 40,
              request.revision.allSatisfy(\.isHexDigit),
              request.requiredPaths.isEmpty == false,
              request.requiredPaths.allSatisfy(Self.isSafeFileName)
        else {
            throw LocalWritingModelInstallFailure.downloadFailed
        }
        return try await client.downloadSnapshot(
            of: repository,
            to: request.destination,
            revision: request.revision,
            matching: request.requiredPaths,
            localFilesOnly: false,
            maxConcurrentDownloads: 4
        )
    }

    private static func isSafeFileName(_ path: String) -> Bool {
        path.isEmpty == false &&
            path != "." &&
            path != ".." &&
            path.contains("/") == false &&
            path.contains("\\") == false
    }
}
