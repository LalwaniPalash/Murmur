import XCTest
@testable import Murmur

final class TransformEngineTests: XCTestCase {
    @MainActor
    func testHeuristicCommandSummarizeTrimsToFirstSentences() async {
        let engine = HybridTransformEngine()
        let transformed = await engine.applyCommand(
            command: "summarize this",
            to: "One. Two. Three. Four.",
            context: .document
        )

        XCTAssertEqual(transformed.text, "One. Two")
    }

    @MainActor
    func testCleanupAddsPunctuationForPlainText() async {
        let engine = HybridTransformEngine()
        let cleaned = await engine.cleanup(
            text: "this is a test",
            level: .light,
            context: .chat,
            styleProfile: nil
        )

        XCTAssertEqual(cleaned.text, "This is a test.")
        XCTAssertFalse(cleaned.usedFallback)
    }

    func testLlamaOutputSanitizerRemovesFollowUpArtifact() {
        let sanitized = HybridTransformEngine.sanitizeLlamaOutput(
            """
            <murmur-output>
            This is the answer.
            Ask for follow-up changes
            </murmur-output>
            Ask for follow-up changes
            """
        )

        XCTAssertEqual(sanitized, "This is the answer.")
    }

    func testLlamaOutputSanitizerRejectsUndelimitedOutput() {
        let sanitized = HybridTransformEngine.sanitizeLlamaOutput("This is the answer.\n\nAsk for follow-up changes")

        XCTAssertNil(sanitized)
    }
}
