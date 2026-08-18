import Foundation
import Testing

@testable import MurmurQualityCore

struct PrivacyAuditTests {
    @Test func findsCanariesWithoutReturningFileContents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-privacy-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("diagnostics.json")
        try Data("prefix TRANSCRIPT-CANARY suffix".utf8).write(to: file)

        let findings = try PrivacyCanaryScanner.scan(
            directory: directory,
            canaries: ["TRANSCRIPT-CANARY", "API-KEY-CANARY"]
        )

        #expect(findings.count == 1)
        #expect(findings[0].relativePath == "diagnostics.json")
        #expect(findings[0].canaryIdentifier != "TRANSCRIPT-CANARY")
        #expect(String(describing: findings).contains("prefix") == false)
    }

    @Test func networkSurfaceAuditRequiresEveryCallSiteToBeAllowlisted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-network-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let approved = directory.appendingPathComponent("ModelInstaller.swift")
        let unexpected = directory.appendingPathComponent("Telemetry.swift")
        try Data("let session = URLSession.shared".utf8).write(to: approved)
        try Data("let task = URLSession.shared.dataTask(with: url)".utf8).write(to: unexpected)

        let result = try NetworkSurfaceAuditor.audit(
            sourceDirectory: directory,
            allowedRelativePaths: ["ModelInstaller.swift"]
        )

        #expect(result.discoveredRelativePaths == ["ModelInstaller.swift", "Telemetry.swift"])
        #expect(result.unapprovedRelativePaths == ["Telemetry.swift"])
        #expect(result.passed == false)
    }
}
