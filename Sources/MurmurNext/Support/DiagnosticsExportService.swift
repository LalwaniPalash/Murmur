import Foundation

struct DiagnosticsExportService: Sendable {
    private struct Report: Encodable {
        let format = "murmur-diagnostics"
        let version = 1
        let generatedAt: Date
        let appVersion: String
        let operatingSystem: String
        let architecture: String
        let historyCount: Int
        let noteCount: Int
        let installedModels: [String]
        let includesPrivateContent: Bool
        let history: [TranscriptRecord]?
        let notes: [ScratchpadNote]?
    }

    func makeReport(
        history: [TranscriptRecord],
        notes: [ScratchpadNote],
        modelIdentifiers: [String],
        includeContent: Bool
    ) throws -> Data {
        let report = Report(
            generatedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            historyCount: history.count,
            noteCount: notes.count,
            installedModels: modelIdentifiers.sorted(),
            includesPrivateContent: includeContent,
            history: includeContent ? history : nil,
            notes: includeContent ? notes : nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    private static var architecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}
