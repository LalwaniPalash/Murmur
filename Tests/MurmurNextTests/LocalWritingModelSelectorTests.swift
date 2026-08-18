import Testing
@testable import MurmurNext

struct LocalWritingModelSelectorTests {
    private let selector = LocalWritingModelSelector()

    @Test func automaticPrefersBalancedForEmail() {
        let selection = selector.select(
            mode: .automatic,
            preferredIdentifier: LocalWritingModelManifest.qwen3_0_6B_4Bit.id,
            operation: .professionalEmail,
            installedIdentifiers: Set(LocalWritingModelManifest.supported.map(\.id))
        )
        #expect(selection?.identifier == LocalWritingModelManifest.llama3_2_1B_4Bit.id)
        #expect(selection?.retryIdentifier == LocalWritingModelManifest.qwen3_1_7B_4Bit.id)
    }

    @Test func automaticPrefersHighestQualityForCommand() {
        let selection = selector.select(
            mode: .automatic,
            preferredIdentifier: "",
            operation: .semanticCommand,
            installedIdentifiers: Set(LocalWritingModelManifest.supported.map(\.id))
        )
        #expect(selection?.identifier == LocalWritingModelManifest.qwen3_1_7B_4Bit.id)
        #expect(selection?.retryIdentifier == nil)
    }

    @Test func preferredFallsBackButFixedFailsClosed() {
        let installed = Set([LocalWritingModelManifest.qwen3_0_6B_4Bit.id])
        #expect(selector.select(
            mode: .preferred,
            preferredIdentifier: "missing",
            operation: .professionalEmail,
            installedIdentifiers: installed
        )?.identifier == LocalWritingModelManifest.qwen3_0_6B_4Bit.id)
        #expect(selector.select(
            mode: .fixed,
            preferredIdentifier: "missing",
            operation: .professionalEmail,
            installedIdentifiers: installed
        ) == nil)
    }
}
