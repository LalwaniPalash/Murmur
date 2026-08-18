import Foundation
import MurmurQualityCore
import Testing

struct RepositoryPrivacyTests {
    @Test func everyMurmurNetworkCallSiteIsExplicitlyAllowlisted() throws {
        let result = try NetworkSurfaceAuditor.audit(
            sourceDirectory: Self.sourceDirectory,
            allowedRelativePaths: [
                "Intelligence/HuggingFaceLocalWritingModelDownloader.swift",
                "Intelligence/ModelInstaller.swift",
                "Intelligence/OpenAITextTransformationEngine.swift",
                "Intelligence/TransformationHTTPClient.swift",
            ]
        )

        #expect(result.unapprovedRelativePaths.isEmpty)
        #expect(result.discoveredRelativePaths == [
            "Intelligence/HuggingFaceLocalWritingModelDownloader.swift",
            "Intelligence/ModelInstaller.swift",
            "Intelligence/OpenAITextTransformationEngine.swift",
            "Intelligence/TransformationHTTPClient.swift",
        ])
    }

    @Test func everyPreferenceAndLoggingSurfaceIsExplicitlyAllowlisted() throws {
        let preferences = try PreferenceSurfaceAuditor.audit(
            sourceDirectory: Self.sourceDirectory,
            allowedRelativePaths: [
                "App/AppEnvironment.swift",
                "Features/FlowBar/FlowBarController.swift",
            ]
        )
        let logging = try LoggingSurfaceAuditor.audit(
            sourceDirectory: Self.sourceDirectory,
            allowedRelativePaths: [
                "App/AppEnvironment.swift",
                "Insertion/TextInsertionCoordinator.swift",
            ]
        )

        #expect(preferences.passed)
        #expect(preferences.discoveredRelativePaths == [
            "App/AppEnvironment.swift",
            "Features/FlowBar/FlowBarController.swift",
        ])
        #expect(logging.passed)
        #expect(logging.discoveredRelativePaths == [
            "App/AppEnvironment.swift",
            "Insertion/TextInsertionCoordinator.swift",
        ])
    }

    @Test func insertionMatrixDeclaresEverySupportedControlFamilyWithoutContent() throws {
        let matrix = try InsertionCompatibilityStore.load(
            from: Self.repository.appendingPathComponent("quality/insertion-matrix.json")
        )
        for record in matrix.records { try record.validate() }

        let declared = Set(matrix.records.map(\.controlType))
        let required = Set(InsertionControlType.allCases.filter { $0 != .unknown })
        #expect(declared == required)
        #expect(matrix.records.allSatisfy { $0.outcome == .untested })
    }

    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let sourceDirectory = repository.appendingPathComponent("Sources/MurmurNext", isDirectory: true)
}
