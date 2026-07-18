import Testing
@testable import MurmurNext

struct LocalCommandEngineTests {
    @Test(arguments: [
        ("make this uppercase", "Hello quiet world.", "HELLO QUIET WORLD."),
        ("make this lowercase", "Hello QUIET World.", "hello quiet world."),
        ("make this concise", "I think that this is really very useful.", "This is useful."),
        ("turn this into bullets", "Apples, bananas, and oranges", "• Apples\n• Bananas\n• Oranges"),
    ])
    func appliesGroundedOfflineTransforms(command: String, selectedText: String, expected: String) async throws {
        let action = try await HeuristicTextTransformEngine().apply(command: command, selectedText: selectedText)
        #expect(action == .replace(expected))
    }

    @Test func recognizesPressEnterWithoutASelection() async throws {
        let action = try await HeuristicTextTransformEngine().apply(command: "press enter", selectedText: nil)
        #expect(action == .pressEnter)
    }

    @Test func refusesUnsupportedUngroundedCommands() async {
        await #expect(throws: TextTransformError.requiresLocalLanguageModel) {
            try await HeuristicTextTransformEngine().apply(command: "translate this to Spanish", selectedText: "Hello")
        }
    }
}
