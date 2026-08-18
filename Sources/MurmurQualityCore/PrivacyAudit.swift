import CryptoKit
import Foundation

public struct PrivacyCanaryFinding: Codable, Equatable, Sendable {
    public let relativePath: String
    public let canaryIdentifier: String
}

public enum PrivacyCanaryScanner {
    public static func scan(
        directory: URL,
        canaries: [String],
        maximumFileSize: Int = 10_000_000
    ) throws -> [PrivacyCanaryFinding] {
        let base = directory.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let nonEmptyCanaries = canaries.filter { !$0.isEmpty }.map { ($0, identifier(for: $0)) }
        var findings: [PrivacyCanaryFinding] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= maximumFileSize else { continue }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            for (canary, identifier) in nonEmptyCanaries where data.range(of: Data(canary.utf8)) != nil {
                findings.append(PrivacyCanaryFinding(
                    relativePath: relativePath(of: url, under: base),
                    canaryIdentifier: identifier
                ))
            }
        }
        return findings.sorted {
            ($0.relativePath, $0.canaryIdentifier) < ($1.relativePath, $1.canaryIdentifier)
        }
    }

    private static func identifier(for canary: String) -> String {
        SHA256.hash(data: Data(canary.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func relativePath(of url: URL, under base: URL) -> String {
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.lastPathComponent
    }
}

public struct NetworkSurfaceAuditResult: Codable, Equatable, Sendable {
    public let discoveredRelativePaths: [String]
    public let unapprovedRelativePaths: [String]
    public var passed: Bool { unapprovedRelativePaths.isEmpty }
}

public enum NetworkSurfaceAuditor {
    public static func audit(
        sourceDirectory: URL,
        allowedRelativePaths: Set<String>
    ) throws -> NetworkSurfaceAuditResult {
        try SwiftSourceSurfaceAuditor.audit(
            sourceDirectory: sourceDirectory,
            markers: ["URLSession", "URLRequest", "NWConnection", "NWListener", "WebSocket"],
            allowedRelativePaths: allowedRelativePaths
        )
    }
}

public enum PreferenceSurfaceAuditor {
    public static func audit(
        sourceDirectory: URL,
        allowedRelativePaths: Set<String>
    ) throws -> NetworkSurfaceAuditResult {
        try SwiftSourceSurfaceAuditor.audit(
            sourceDirectory: sourceDirectory,
            markers: ["UserDefaults"],
            allowedRelativePaths: allowedRelativePaths
        )
    }
}

public enum LoggingSurfaceAuditor {
    public static func audit(
        sourceDirectory: URL,
        allowedRelativePaths: Set<String>
    ) throws -> NetworkSurfaceAuditResult {
        try SwiftSourceSurfaceAuditor.audit(
            sourceDirectory: sourceDirectory,
            markers: ["Logger("],
            allowedRelativePaths: allowedRelativePaths
        )
    }
}

private enum SwiftSourceSurfaceAuditor {
    static func audit(
        sourceDirectory: URL,
        markers: [String],
        allowedRelativePaths: Set<String>
    ) throws -> NetworkSurfaceAuditResult {
        let base = sourceDirectory.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return NetworkSurfaceAuditResult(discoveredRelativePaths: [], unapprovedRelativePaths: [])
        }
        var discovered: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            guard markers.contains(where: source.contains) else { continue }
            let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
            discovered.insert(url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.lastPathComponent)
        }
        let sorted = discovered.sorted()
        return NetworkSurfaceAuditResult(
            discoveredRelativePaths: sorted,
            unapprovedRelativePaths: sorted.filter { !allowedRelativePaths.contains($0) }
        )
    }
}
