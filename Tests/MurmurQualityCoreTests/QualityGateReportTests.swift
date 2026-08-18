import Foundation
import Testing

@testable import MurmurQualityCore

struct QualityGateReportTests {
    @Test func reportContainsOnlyAggregateEvidence() throws {
        let report = QualityGateReport(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            baselineCommit: "abc123",
            checks: [
                QualityGateCheck(id: "EVAL-002", status: .passed, summary: "3 fixtures passed"),
                QualityGateCheck(id: "EVAL-007", status: .notRun, summary: "manual matrix unavailable"),
            ]
        )
        let data = try QualityJSON.encoder.encode(report)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("abc123"))
        #expect(text.contains("3 fixtures passed"))
        #expect(text.contains("transcript") == false)
        #expect(text.contains("audioPath") == false)
    }

    @Test func overallStatusFailsOnlyForFailedChecks() {
        let incomplete = QualityGateReport(
            generatedAt: .distantPast,
            baselineCommit: nil,
            checks: [QualityGateCheck(id: "one", status: .notRun, summary: "not run")]
        )
        let failed = QualityGateReport(
            generatedAt: .distantPast,
            baselineCommit: nil,
            checks: [QualityGateCheck(id: "one", status: .failed, summary: "failed")]
        )

        #expect(incomplete.overallStatus == .incomplete)
        #expect(failed.overallStatus == .failed)
    }
}
