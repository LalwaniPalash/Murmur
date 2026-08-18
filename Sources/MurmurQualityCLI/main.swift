import Foundation
import MurmurQualityCore

@main
struct MurmurQualityCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("murmur-quality: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }
        switch command {
        case "corpus":
            try runCorpus(Array(arguments.dropFirst()))
        case "benchmark":
            try runBenchmark(Array(arguments.dropFirst()))
        case "insertion":
            try runInsertion(Array(arguments.dropFirst()))
        case "privacy":
            try runPrivacy(Array(arguments.dropFirst()))
        case "network":
            try runNetwork(Array(arguments.dropFirst()))
        case "gate":
            try runGate(Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            printUsage()
        default:
            throw CLIError.usage("Unknown command: \(command)")
        }
    }

    private static func runCorpus(_ arguments: [String]) throws {
        if arguments.first == "validate", arguments.count == 3 {
            let manifestURL = URL(fileURLWithPath: arguments[1])
            let baseURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
            let manifest = try CorpusManifestLoader.load(from: manifestURL)
            _ = try CorpusManifestValidator.validate(manifest, baseDirectory: baseURL)
            print("Validated \(manifest.fixtures.count) corpus fixture(s).")
            return
        }
        if arguments.first == "evaluate", arguments.count == 2 {
            let report = try decode(CorpusQualityReport.self, from: arguments[1])
            print(
                "Corpus: \(report.completedFixtureCount) completed, "
                    + "\(report.failedFixtureCount) failed, \(report.skippedFixtureCount) skipped."
            )
            if report.failedFixtureCount > 0 { Foundation.exit(2) }
            if report.skippedFixtureCount > 0 || report.completedFixtureCount == 0 { Foundation.exit(3) }
            return
        }
        throw CLIError.usage("""
        Usage:
          murmur-quality corpus validate <manifest.json> <base-directory>
          murmur-quality corpus evaluate <corpus-report.json>
        """)
    }

    private static func runBenchmark(_ arguments: [String]) throws {
        if arguments.first == "merge", arguments.count >= 4 {
            var combined: [BenchmarkSample] = []
            for path in arguments.dropFirst(2) {
                combined += try decode([BenchmarkSample].self, from: path)
            }
            try write(combined, to: arguments[1])
            print("Merged \(combined.count) benchmark sample(s).")
            return
        }
        if arguments.first == "summarize", arguments.count == 3 {
            let samples = try QualityJSON.decoder.decode(
                [BenchmarkSample].self,
                from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let report = BenchmarkSummarizer.summarize(samples)
            try write(report, to: arguments[2])
            print("Summarized \(samples.count) benchmark sample(s).")
            return
        }
        if arguments.first == "compare", arguments.count == 6,
           let tolerance = Double(arguments[4]), let minimumSampleCount = Int(arguments[5]) {
            let current = try decode(BenchmarkReport.self, from: arguments[1])
            let baseline = try decode(BenchmarkReport.self, from: arguments[2])
            let comparison = BenchmarkRegressionComparator.compare(
                current: current,
                baseline: baseline,
                relativeTolerance: tolerance,
                minimumSampleCount: minimumSampleCount
            )
            try write(comparison, to: arguments[3])
            print("Benchmark comparison: \(comparison.status.rawValue)")
            if comparison.status == .regressed { Foundation.exit(2) }
            if comparison.status == .insufficientEvidence { Foundation.exit(3) }
            return
        }
        throw CLIError.usage("""
        Usage:
          murmur-quality benchmark merge <combined-samples.json> <samples.json> <samples.json> [...]
          murmur-quality benchmark summarize <samples.json> <report.json>
          murmur-quality benchmark compare <current.json> <baseline.json> <comparison.json> <relative-tolerance> <minimum-samples>
        """)
    }

    private static func runInsertion(_ arguments: [String]) throws {
        if arguments.first == "summarize", arguments.count == 2 {
            let matrix = try InsertionCompatibilityStore.load(from: URL(fileURLWithPath: arguments[1]))
            let summary = InsertionCompatibilitySummary(records: matrix.records)
            let data = try QualityJSON.encoder.encode(summary)
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }
        if arguments.first == "record", arguments.count == 3 {
            let record = try decode(InsertionCompatibilityRecord.self, from: arguments[2])
            try InsertionCompatibilityStore.append(record, to: URL(fileURLWithPath: arguments[1]))
            print("Recorded \(record.applicationName) \(record.applicationVersion) / \(record.controlType.rawValue).")
            return
        }
        if arguments.first == "evaluate", arguments.count == 3, let minimumRate = Double(arguments[2]) {
            let matrix = try InsertionCompatibilityStore.load(from: URL(fileURLWithPath: arguments[1]))
            let summary = InsertionCompatibilitySummary(records: matrix.records)
            let data = try QualityJSON.encoder.encode(summary)
            print(String(data: data, encoding: .utf8) ?? "{}")
            if summary.testedCount < summary.totalRecordCount || summary.testedCount == 0 {
                Foundation.exit(3)
            }
            if summary.successfulOrRecoverableRate < minimumRate { Foundation.exit(2) }
            return
        }
        throw CLIError.usage("""
        Usage:
          murmur-quality insertion summarize <matrix.json>
          murmur-quality insertion record <matrix.json> <content-free-record.json>
          murmur-quality insertion evaluate <matrix.json> <minimum-successful-or-recoverable-rate>
        """)
    }

    private static func runPrivacy(_ arguments: [String]) throws {
        guard arguments.count >= 3, arguments.first == "scan" else {
            throw CLIError.usage("Usage: murmur-quality privacy scan <directory> <canary> [canary ...]")
        }
        let findings = try PrivacyCanaryScanner.scan(
            directory: URL(fileURLWithPath: arguments[1], isDirectory: true),
            canaries: Array(arguments.dropFirst(2))
        )
        let data = try QualityJSON.encoder.encode(findings)
        print(String(data: data, encoding: .utf8) ?? "[]")
        if !findings.isEmpty { Foundation.exit(2) }
    }

    private static func runNetwork(_ arguments: [String]) throws {
        guard arguments.count >= 2, arguments.first == "audit" else {
            throw CLIError.usage("Usage: murmur-quality network audit <source-directory> [allowed-relative-path ...]")
        }
        let result = try NetworkSurfaceAuditor.audit(
            sourceDirectory: URL(fileURLWithPath: arguments[1], isDirectory: true),
            allowedRelativePaths: Set(arguments.dropFirst(2))
        )
        let data = try QualityJSON.encoder.encode(result)
        print(String(data: data, encoding: .utf8) ?? "{}")
        if !result.passed { Foundation.exit(2) }
    }

    private static func runGate(_ arguments: [String]) throws {
        guard arguments.first == "report", arguments.count >= 3 else {
            throw CLIError.usage("Usage: murmur-quality gate report <output.json> <id=status:summary> [...]")
        }
        let checks = try arguments.dropFirst(2).map(parseCheck)
        let report = QualityGateReport(
            generatedAt: Date(),
            baselineCommit: ProcessInfo.processInfo.environment["MURMUR_BASELINE_COMMIT"],
            checks: checks
        )
        try write(report, to: arguments[1])
        print("Quality gate: \(report.overallStatus.rawValue)")
    }

    private static func parseCheck(_ value: String) throws -> QualityGateCheck {
        let pair = value.split(separator: "=", maxSplits: 1).map(String.init)
        guard pair.count == 2 else { throw CLIError.usage("Invalid gate check: \(value)") }
        let detail = pair[1].split(separator: ":", maxSplits: 1).map(String.init)
        guard detail.count == 2, let status = QualityGateCheckStatus(rawValue: detail[0]) else {
            throw CLIError.usage("Invalid gate check: \(value)")
        }
        return QualityGateCheck(id: pair[0], status: status, summary: detail[1])
    }

    private static func write<Value: Encodable>(_ value: Value, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try QualityJSON.encoder.encode(value).write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from path: String) throws -> Value {
        try QualityJSON.decoder.decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    private static func printUsage() {
        print("""
        Murmur quality tools

          corpus validate <manifest.json> <base-directory>
          corpus evaluate <corpus-report.json>
          benchmark summarize <samples.json> <report.json>
          benchmark merge <combined-samples.json> <samples.json> <samples.json> [...]
          benchmark compare <current.json> <baseline.json> <comparison.json> <relative-tolerance> <minimum-samples>
          insertion summarize <matrix.json>
          insertion record <matrix.json> <content-free-record.json>
          insertion evaluate <matrix.json> <minimum-successful-or-recoverable-rate>
          privacy scan <directory> <canary> [canary ...]
          network audit <source-directory> [allowed-relative-path ...]
          gate report <output.json> <id=status:summary> [...]
        """)
    }
}

private enum CLIError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): message
        }
    }
}
