import Foundation
import Testing

@testable import MurmurQualityCore

struct InsertionCompatibilityTests {
    @Test func recordsContentFreeManualCompatibilityResult() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-insertion-matrix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("matrix.json")
        let record = InsertionCompatibilityRecord(
            applicationName: "Example Editor",
            bundleIdentifier: "com.example.editor",
            applicationVersion: "1.2.3",
            controlType: .chromiumContentEditable,
            strategy: .clipboardPaste,
            outcome: .supported,
            verification: .observed,
            recovery: .notNeeded,
            notes: "Paste and clipboard restoration succeeded."
        )

        try InsertionCompatibilityStore.append(record, to: url)
        let matrix = try InsertionCompatibilityStore.load(from: url)
        let data = try Data(contentsOf: url)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(matrix.records == [record])
        #expect(text.contains("Example Editor"))
        #expect(text.contains("transcript") == false)
        #expect(text.contains("dictatedText") == false)
    }

    @Test func computesSuccessfulOrRecoverableRate() {
        let records = [
            Self.record(outcome: .supported),
            Self.record(outcome: .recoverable),
            Self.record(outcome: .unsupported),
            Self.record(outcome: .untested),
        ]
        let summary = InsertionCompatibilitySummary(records: records)

        #expect(summary.testedCount == 3)
        #expect(summary.successfulOrRecoverableCount == 2)
        #expect(abs(summary.successfulOrRecoverableRate - (2.0 / 3.0)) < 0.000_001)
    }

    @Test func realResultReplacesItsPendingSeedInsteadOfLeavingTheGateIncomplete() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-insertion-upsert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("matrix.json")
        let pending = InsertionCompatibilityRecord(
            applicationName: "Example Editor",
            bundleIdentifier: "com.example.editor",
            applicationVersion: "pending",
            controlType: .nativeTextView,
            strategy: .none,
            outcome: .untested,
            verification: .unknown,
            recovery: .notNeeded,
            notes: nil
        )
        try QualityJSON.encoder.encode(InsertionCompatibilityMatrix(records: [pending]))
            .write(to: url, options: [.atomic])

        let tested = Self.record(outcome: .supported)
        try InsertionCompatibilityStore.append(tested, to: url)
        let matrix = try InsertionCompatibilityStore.load(from: url)

        #expect(matrix.records == [tested])
        #expect(InsertionCompatibilitySummary(records: matrix.records).testedCount == 1)
    }

    @Test func rejectsPrivateOrOversizedNotes() {
        #expect(throws: InsertionCompatibilityValidationError.self) {
            _ = try InsertionCompatibilityRecord.validated(
                applicationName: "Editor",
                bundleIdentifier: "com.example.editor",
                applicationVersion: "1",
                controlType: .nativeTextView,
                strategy: .accessibilityWrite,
                outcome: .supported,
                verification: .observed,
                recovery: .notNeeded,
                notes: "dictatedText=secret customer sentence"
            )
        }
        #expect(throws: InsertionCompatibilityValidationError.self) {
            _ = try InsertionCompatibilityRecord.validated(
                applicationName: "Editor",
                bundleIdentifier: "com.example.editor",
                applicationVersion: "1",
                controlType: .nativeTextView,
                strategy: .accessibilityWrite,
                outcome: .supported,
                verification: .observed,
                recovery: .notNeeded,
                notes: String(repeating: "x", count: 2_001)
            )
        }
    }

    private static func record(outcome: InsertionCompatibilityOutcome) -> InsertionCompatibilityRecord {
        InsertionCompatibilityRecord(
            applicationName: "Editor",
            bundleIdentifier: "com.example.editor",
            applicationVersion: "1",
            controlType: .nativeTextView,
            strategy: .clipboardPaste,
            outcome: outcome,
            verification: .observed,
            recovery: outcome == .recoverable ? .clipboard : .notNeeded,
            notes: nil
        )
    }
}
