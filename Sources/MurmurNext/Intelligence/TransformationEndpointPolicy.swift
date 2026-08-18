import Foundation

enum TransformationEndpointError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL
    case unsupportedScheme
    case insecureRemoteEndpoint
    case credentialsInURL
    case fragmentNotAllowed
    case invalidRoute

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a complete provider URL with a host."
        case .unsupportedScheme: "Provider URLs must use HTTPS, or HTTP on this Mac."
        case .insecureRemoteEndpoint: "Remote provider URLs must use HTTPS."
        case .credentialsInURL: "Store provider credentials in Keychain, not in the URL."
        case .fragmentNotAllowed: "Provider URLs cannot contain a fragment."
        case .invalidRoute: "The provider API route is invalid."
        }
    }
}

enum TransformationEndpointPolicy {
    static func validate(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              host.isEmpty == false
        else { throw TransformationEndpointError.invalidURL }
        guard scheme == "https" || scheme == "http" else {
            throw TransformationEndpointError.unsupportedScheme
        }
        guard components.user == nil, components.password == nil else {
            throw TransformationEndpointError.credentialsInURL
        }
        guard components.fragment == nil else {
            throw TransformationEndpointError.fragmentNotAllowed
        }
        if scheme == "http" && isLoopback(host) == false {
            throw TransformationEndpointError.insecureRemoteEndpoint
        }
        components.scheme = scheme
        components.host = host
        if components.path.count > 1 {
            components.path = components.path.replacingOccurrences(
                of: #"/+$"#,
                with: "",
                options: .regularExpression
            )
        }
        guard let url = components.url else { throw TransformationEndpointError.invalidURL }
        return url
    }

    static func endpoint(base: URL, route: String) throws -> URL {
        let route = route.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard route.isEmpty == false,
              route.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." })
        else { throw TransformationEndpointError.invalidRoute }
        return base.appending(path: route)
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }
}
