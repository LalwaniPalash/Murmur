import Testing
@testable import MurmurNext

struct TextInsertionPolicyTests {
    @Test func clipboardRestoreNeverOverwritesANewerUserCopy() {
        #expect(ClipboardTransactionPolicy.shouldRestore(injectedChangeCount: 12, currentChangeCount: 12))
        #expect(ClipboardTransactionPolicy.shouldRestore(injectedChangeCount: 12, currentChangeCount: 13) == false)
    }
}
