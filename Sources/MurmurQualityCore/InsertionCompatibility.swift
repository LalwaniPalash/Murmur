import Foundation

public enum InsertionControlType: String, Codable, CaseIterable, Equatable, Sendable {
    case nativeTextField
    case nativeTextView
    case swiftUITextEditor
    case chromiumContentEditable
    case browserTextArea
    case terminal
    case javaOrQt
    case officeDocument
    case remoteDesktop
    case secureInput
    case unknown
}

public enum InsertionStrategy: String, Codable, CaseIterable, Equatable, Sendable {
    case clipboardPaste
    case accessibilityWrite
    case directTyping
    case none
}

public enum InsertionCompatibilityOutcome: String, Codable, CaseIterable, Equatable, Sendable {
    case supported
    case recoverable
    case unsupported
    case untested
}

public enum InsertionVerification: String, Codable, CaseIterable, Equatable, Sendable {
    case observed
    case verifiedByAccessibility
    case unknown
    case failed
}

public enum InsertionRecovery: String, Codable, CaseIterable, Equatable, Sendable {
    case notNeeded
    case clipboard
    case history
    case failed
}

public struct InsertionCompatibilityRecord: Codable, Equatable, Sendable {
    public let applicationName: String
    public let bundleIdentifier: String
    public let applicationVersion: String
    public let controlType: InsertionControlType
    public let strategy: InsertionStrategy
    public let outcome: InsertionCompatibilityOutcome
    public let verification: InsertionVerification
    public let recovery: InsertionRecovery
    public let notes: String?

    public init(
        applicationName: String,
        bundleIdentifier: String,
        applicationVersion: String,
        controlType: InsertionControlType,
        strategy: InsertionStrategy,
        outcome: InsertionCompatibilityOutcome,
        verification: InsertionVerification,
        recovery: InsertionRecovery,
        notes: String?
    ) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.applicationVersion = applicationVersion
        self.controlType = controlType
        self.strategy = strategy
        self.outcome = outcome
        self.verification = verification
        self.recovery = recovery
        self.notes = notes
    }

    public static func validated(
        applicationName: String,
        bundleIdentifier: String,
        applicationVersion: String,
        controlType: InsertionControlType,
        strategy: InsertionStrategy,
        outcome: InsertionCompatibilityOutcome,
        verification: InsertionVerification,
        recovery: InsertionRecovery,
        notes: String?
    ) throws -> InsertionCompatibilityRecord {
        let record = InsertionCompatibilityRecord(
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            applicationVersion: applicationVersion,
            controlType: controlType,
            strategy: strategy,
            outcome: outcome,
            verification: verification,
            recovery: recovery,
            notes: notes
        )
        try record.validate()
        return record
    }

    public func validate() throws {
        guard !applicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !applicationVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw InsertionCompatibilityValidationError.missingApplicationMetadata }
        if let notes {
            guard notes.count <= 2_000 else {
                throw InsertionCompatibilityValidationError.notesTooLong
            }
            let lowered = notes.lowercased()
            guard !lowered.contains("dictatedtext=") && !lowered.contains("transcript=") else {
                throw InsertionCompatibilityValidationError.privateContentField
            }
        }
    }
}

public enum InsertionCompatibilityValidationError: Error, Equatable, Sendable {
    case missingApplicationMetadata
    case notesTooLong
    case privateContentField
}

public struct InsertionCompatibilityMatrix: Codable, Equatable, Sendable {
    public let format: String
    public let version: Int
    public var records: [InsertionCompatibilityRecord]

    public init(records: [InsertionCompatibilityRecord] = []) {
        format = "murmur-insertion-matrix"
        version = 1
        self.records = records
    }
}

public enum InsertionCompatibilityStore {
    public static func load(from url: URL) throws -> InsertionCompatibilityMatrix {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return InsertionCompatibilityMatrix()
        }
        return try QualityJSON.decoder.decode(
            InsertionCompatibilityMatrix.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        )
    }

    public static func append(_ record: InsertionCompatibilityRecord, to url: URL) throws {
        try record.validate()
        var matrix = try load(from: url)
        if let pendingIndex = matrix.records.firstIndex(where: {
            $0.bundleIdentifier == record.bundleIdentifier
                && $0.controlType == record.controlType
                && ($0.applicationVersion == record.applicationVersion || $0.applicationVersion == "pending")
        }) {
            matrix.records[pendingIndex] = record
        } else {
            matrix.records.append(record)
        }
        matrix.records.sort {
            ($0.bundleIdentifier, $0.applicationVersion, $0.controlType.rawValue)
                < ($1.bundleIdentifier, $1.applicationVersion, $1.controlType.rawValue)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try QualityJSON.encoder.encode(matrix).write(to: url, options: [.atomic, .completeFileProtection])
    }
}

public struct InsertionCompatibilitySummary: Codable, Equatable, Sendable {
    public let totalRecordCount: Int
    public let testedCount: Int
    public let successfulOrRecoverableCount: Int
    public let successfulOrRecoverableRate: Double

    public init(records: [InsertionCompatibilityRecord]) {
        totalRecordCount = records.count
        let tested = records.filter { $0.outcome != .untested }
        testedCount = tested.count
        successfulOrRecoverableCount = tested.filter {
            $0.outcome == .supported || $0.outcome == .recoverable
        }.count
        successfulOrRecoverableRate = tested.isEmpty
            ? 0
            : Double(successfulOrRecoverableCount) / Double(tested.count)
    }
}
