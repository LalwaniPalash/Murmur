import Testing

@testable import MurmurQualityCore

struct BenchmarkReportTests {
    @Test func assignsRequiredDurationBuckets() {
        #expect(RecordingDurationBucket(seconds: 0.5) == .underOneSecond)
        #expect(RecordingDurationBucket(seconds: 2) == .oneToThreeSeconds)
        #expect(RecordingDurationBucket(seconds: 7) == .threeToTenSeconds)
        #expect(RecordingDurationBucket(seconds: 20) == .tenToThirtySeconds)
        #expect(RecordingDurationBucket(seconds: 90) == .thirtyToOneHundredTwentySeconds)
        #expect(RecordingDurationBucket(seconds: 180) == .meetingScale)
    }

    @Test func summarizesP50AndP95WithoutTreatingSingleRunAsARegression() {
        let samples = (1...20).map { index in
            BenchmarkSample(
                stage: .totalRelease,
                recordingDurationSeconds: 2,
                elapsedMilliseconds: Double(index * 10),
                hardwareIdentifier: "Mac14,2",
                modelIdentifier: "small.en"
            )
        }

        let report = BenchmarkSummarizer.summarize(samples)
        let summary = report.groups.first

        #expect(summary?.sampleCount == 20)
        #expect(summary?.p50Milliseconds == 105)
        #expect(summary?.p95Milliseconds == 190.5)

        let oneSample = BenchmarkSummarizer.summarize([samples[0]])
        let comparison = BenchmarkRegressionComparator.compare(
            current: oneSample,
            baseline: report,
            relativeTolerance: 0.1,
            minimumSampleCount: 5
        )
        #expect(comparison.status == .insufficientEvidence)
    }

    @Test func flagsMeaningfulP95RegressionAgainstMatchingBaseline() {
        func report(milliseconds: [Double]) -> BenchmarkReport {
            BenchmarkSummarizer.summarize(milliseconds.map {
                BenchmarkSample(
                    stage: .transcription,
                    recordingDurationSeconds: 5,
                    elapsedMilliseconds: $0,
                    hardwareIdentifier: "Mac14,2",
                    modelIdentifier: "small.en"
                )
            })
        }

        let baseline = report(milliseconds: [100, 101, 102, 103, 104, 105, 106, 107])
        let current = report(milliseconds: [150, 151, 152, 153, 154, 155, 156, 157])
        let comparison = BenchmarkRegressionComparator.compare(
            current: current,
            baseline: baseline,
            relativeTolerance: 0.1,
            minimumSampleCount: 5
        )

        #expect(comparison.status == .regressed)
        #expect(comparison.regressions.count == 1)
    }
}
