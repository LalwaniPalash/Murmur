import Foundation
import Testing
@testable import MurmurNext

struct DiagnosticsExportServiceTests {
    @Test func redactedReportNeverContainsDictationOrNoteContent() throws {
        let history = [
            TranscriptRecord(
                id: UUID(),
                createdAt: .now,
                sourceApplication: "SecretEditor",
                sourceBundleIdentifier: "com.example.secret",
                context: .document,
                mode: .pushToTalk,
                text: "top secret dictated launch phrase",
                duration: 4,
                wordsPerMinute: 70,
                insertionSucceeded: true
            ),
        ]
        let notes = [
            ScratchpadNote(
                id: UUID(),
                title: "private roadmap",
                body: "confidential note body",
                isPinned: false,
                createdAt: .now,
                updatedAt: .now
            ),
        ]
        let data = try DiagnosticsExportService().makeReport(
            history: history,
            notes: notes,
            modelIdentifiers: ["large-v3-turbo"],
            includeContent: false
        )
        let report = String(decoding: data, as: UTF8.self)

        #expect(report.contains("top secret dictated launch phrase") == false)
        #expect(report.contains("private roadmap") == false)
        #expect(report.contains("confidential note body") == false)
        #expect(report.contains("SecretEditor") == false)
        #expect(report.contains("\"historyCount\" : 1"))
    }

    @Test func contentInclusiveReportRequiresExplicitOption() throws {
        let record = TranscriptRecord(
            id: UUID(),
            createdAt: .now,
            sourceApplication: "Mail",
            sourceBundleIdentifier: nil,
            context: .email,
            mode: .pushToTalk,
            text: "include this exact phrase",
            duration: 2,
            wordsPerMinute: 90,
            insertionSucceeded: true
        )
        let data = try DiagnosticsExportService().makeReport(
            history: [record],
            notes: [],
            modelIdentifiers: [],
            includeContent: true
        )
        #expect(String(decoding: data, as: UTF8.self).contains(record.text))
    }
}
