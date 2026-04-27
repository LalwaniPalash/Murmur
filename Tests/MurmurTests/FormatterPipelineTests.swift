import XCTest
@testable import Murmur

final class FormatterPipelineTests: XCTestCase {
    func testSnippetExpansionWinsForExactTrigger() {
        let output = FormatterPipeline().format(
            transcript: "my schedule link",
            context: .chat,
            cleanupLevel: .light,
            personalization: .default
        )

        XCTAssertEqual(output, "https://cal.com/murmur/demo")
    }

    func testDeveloperLexiconPreservesCodeTerms() {
        let output = FormatterPipeline().format(
            transcript: "update the git ignore and dot env in snake case",
            context: .code,
            cleanupLevel: .medium,
            personalization: .default
        )

        XCTAssertTrue(output.contains(".gitignore"))
        XCTAssertTrue(output.contains(".env"))
        XCTAssertTrue(output.contains("snake_case"))
    }

    func testPunctuationCommandsConvertSpokenTokens() {
        let output = FormatterPipeline().format(
            transcript: "hello comma world question mark",
            context: .chat,
            cleanupLevel: .light,
            personalization: .default
        )

        XCTAssertEqual(output, "Hello, world?")
    }
}
