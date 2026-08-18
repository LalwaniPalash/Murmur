import Foundation

public enum BenchmarkStage: String, Codable, CaseIterable, Equatable, Sendable {
    case warmup
    case captureDrain
    case transcription
    case repair
    case grounding
    case insertion
    case totalRelease
}

public enum RecordingDurationBucket: String, Codable, CaseIterable, Comparable, Equatable, Sendable {
    case underOneSecond
    case oneToThreeSeconds
    case threeToTenSeconds
    case tenToThirtySeconds
    case thirtyToOneHundredTwentySeconds
    case meetingScale

    public init(seconds: Double) {
        switch max(0, seconds) {
        case ..<1: self = .underOneSecond
        case ..<3: self = .oneToThreeSeconds
        case ..<10: self = .threeToTenSeconds
        case ..<30: self = .tenToThirtySeconds
        case ..<120: self = .thirtyToOneHundredTwentySeconds
        default: self = .meetingScale
        }
    }

    public static func < (lhs: RecordingDurationBucket, rhs: RecordingDurationBucket) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public struct BenchmarkSample: Codable, Equatable, Sendable {
    public let stage: BenchmarkStage
    public let recordingDurationSeconds: Double
    public let elapsedMilliseconds: Double
    public let hardwareIdentifier: String
    public let modelIdentifier: String

    public init(
        stage: BenchmarkStage,
        recordingDurationSeconds: Double,
        elapsedMilliseconds: Double,
        hardwareIdentifier: String,
        modelIdentifier: String
    ) {
        self.stage = stage
        self.recordingDurationSeconds = recordingDurationSeconds
        self.elapsedMilliseconds = elapsedMilliseconds
        self.hardwareIdentifier = hardwareIdentifier
        self.modelIdentifier = modelIdentifier
    }
}

public struct BenchmarkGroup: Codable, Equatable, Sendable {
    public let stage: BenchmarkStage
    public let durationBucket: RecordingDurationBucket
    public let hardwareIdentifier: String
    public let modelIdentifier: String
    public let sampleCount: Int
    public let p50Milliseconds: Double
    public let p95Milliseconds: Double
}

public struct BenchmarkReport: Codable, Equatable, Sendable {
    public let format: String
    public let version: Int
    public let groups: [BenchmarkGroup]

    public init(
        groups: [BenchmarkGroup],
        format: String = "murmur-performance",
        version: Int = 1
    ) {
        self.format = format
        self.version = version
        self.groups = groups
    }
}

public enum BenchmarkSummarizer {
    public static func summarize(_ samples: [BenchmarkSample]) -> BenchmarkReport {
        struct Key: Hashable {
            let stage: BenchmarkStage
            let durationBucket: RecordingDurationBucket
            let hardware: String
            let model: String
        }
        let valid = samples.filter {
            $0.recordingDurationSeconds.isFinite && $0.recordingDurationSeconds >= 0
                && $0.elapsedMilliseconds.isFinite && $0.elapsedMilliseconds >= 0
        }
        let grouped = Dictionary(grouping: valid) {
            Key(
                stage: $0.stage,
                durationBucket: RecordingDurationBucket(seconds: $0.recordingDurationSeconds),
                hardware: $0.hardwareIdentifier,
                model: $0.modelIdentifier
            )
        }
        let groups = grouped.map { key, values in
            let timings = values.map(\.elapsedMilliseconds).sorted()
            return BenchmarkGroup(
                stage: key.stage,
                durationBucket: key.durationBucket,
                hardwareIdentifier: key.hardware,
                modelIdentifier: key.model,
                sampleCount: timings.count,
                p50Milliseconds: percentile(timings, 0.5),
                p95Milliseconds: percentile(timings, 0.95)
            )
        }.sorted {
            ($0.hardwareIdentifier, $0.modelIdentifier, $0.stage.rawValue, $0.durationBucket)
                < ($1.hardwareIdentifier, $1.modelIdentifier, $1.stage.rawValue, $1.durationBucket)
        }
        return BenchmarkReport(groups: groups)
    }

    private static func percentile(_ sorted: [Double], _ percentile: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = percentile * Double(sorted.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + ((sorted[upper] - sorted[lower]) * fraction)
    }
}

public enum BenchmarkComparisonStatus: String, Codable, Equatable, Sendable {
    case passed
    case regressed
    case insufficientEvidence
}

public struct BenchmarkRegression: Codable, Equatable, Sendable {
    public let current: BenchmarkGroup
    public let baseline: BenchmarkGroup
    public let relativeIncrease: Double
}

public struct BenchmarkComparison: Codable, Equatable, Sendable {
    public let status: BenchmarkComparisonStatus
    public let regressions: [BenchmarkRegression]
    public let comparedGroupCount: Int
}

public enum BenchmarkRegressionComparator {
    public static func compare(
        current: BenchmarkReport,
        baseline: BenchmarkReport,
        relativeTolerance: Double,
        minimumSampleCount: Int
    ) -> BenchmarkComparison {
        var regressions: [BenchmarkRegression] = []
        var compared = 0
        var insufficient = false
        for currentGroup in current.groups {
            guard let baselineGroup = baseline.groups.first(where: {
                $0.stage == currentGroup.stage
                    && $0.durationBucket == currentGroup.durationBucket
                    && $0.hardwareIdentifier == currentGroup.hardwareIdentifier
                    && $0.modelIdentifier == currentGroup.modelIdentifier
            }) else {
                insufficient = true
                continue
            }
            guard currentGroup.sampleCount >= minimumSampleCount,
                  baselineGroup.sampleCount >= minimumSampleCount,
                  baselineGroup.p95Milliseconds > 0
            else {
                insufficient = true
                continue
            }
            compared += 1
            let increase = (currentGroup.p95Milliseconds - baselineGroup.p95Milliseconds)
                / baselineGroup.p95Milliseconds
            if increase > relativeTolerance {
                regressions.append(BenchmarkRegression(
                    current: currentGroup,
                    baseline: baselineGroup,
                    relativeIncrease: increase
                ))
            }
        }
        let status: BenchmarkComparisonStatus
        if !regressions.isEmpty {
            status = .regressed
        } else if insufficient || compared == 0 {
            status = .insufficientEvidence
        } else {
            status = .passed
        }
        return BenchmarkComparison(status: status, regressions: regressions, comparedGroupCount: compared)
    }
}
