import Foundation

struct TransformationHTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let data: Data
}

protocol TransformationHTTPTransport: Sendable {
    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws -> TransformationHTTPResponse
}

actor URLSessionTransformationHTTPTransport: TransformationHTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(
            configuration: configuration,
            delegate: TransformationRedirectBlocker(),
            delegateQueue: nil
        )
    }

    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws -> TransformationHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(maximumResponseBytes) {
            throw TransformationProviderFailure.oversizedResponse
        }
        guard let http = response as? HTTPURLResponse else {
            throw TransformationProviderFailure.malformedResponse
        }
        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumResponseBytes))
        }
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else {
                throw TransformationProviderFailure.oversizedResponse
            }
            data.append(byte)
        }
        return TransformationHTTPResponse(statusCode: http.statusCode, data: data)
    }
}

private final class TransformationRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Never forward a bearer credential to a redirected origin. Provider endpoints
        // must be configured at their final HTTPS or loopback URL.
        completionHandler(nil)
    }
}
