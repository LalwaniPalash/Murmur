import AppKit
import CoreGraphics
import Testing
@testable import MurmurNext

struct TextInsertionPolicyTests {
    @Test func clipboardRestoreNeverOverwritesANewerUserCopy() {
        #expect(ClipboardTransactionPolicy.shouldRestore(injectedChangeCount: 12, currentChangeCount: 12))
        #expect(ClipboardTransactionPolicy.shouldRestore(injectedChangeCount: 12, currentChangeCount: 13) == false)
    }
}

/// Main-actor isolated on purpose: Text Input Services aborts the process when its
/// `TISCopyCurrent…` calls run off the main thread, which is exactly how this suite first
/// caught the isolation bug.
@MainActor
struct KeyboardLayoutKeyCodeTests {
    /// Guards the reason this lookup exists: hardcoding ANSI 9 for "v" posts ⌘K on Dvorak.
    /// The assertion is layout-independent on purpose — it checks the code round-trips back
    /// to "v" under whatever layout the machine running the suite happens to use.
    @Test func resolvesTheKeyCodeThatTypesVUnderTheActiveLayout() throws {
        let keyCode = try #require(KeyboardLayoutKeyCodes.keyCode(for: "v"))
        #expect(keyCode <= 127)
        #expect(KeyboardLayoutKeyCodes.keyCode(for: "v") == keyCode)
    }

    @Test func returnsNilForACharacterNoKeyProduces() {
        #expect(KeyboardLayoutKeyCodes.keyCode(for: "🙂") == nil)
    }
}

struct ModifierQuiescencePolicyTests {
    @Test func commandAloneIsQuiet() {
        // ⌘V asks for command; the user still holding it changes nothing.
        #expect(ModifierQuiescencePolicy.isQuiet(.maskCommand))
        #expect(ModifierQuiescencePolicy.isQuiet([]))
    }

    @Test(
        "Modifiers that rewrite ⌘V into another shortcut are not quiet",
        arguments: [CGEventFlags.maskControl, .maskShift, .maskAlternate, .maskSecondaryFn]
    )
    func heldModifiersBlockPasting(flag: CGEventFlags) {
        #expect(ModifierQuiescencePolicy.isQuiet(flag) == false)
        #expect(ModifierQuiescencePolicy.contamination(in: [flag, .maskCommand]) == flag)
    }

    /// Command mode is Ctrl+Fn, and Ctrl routinely outlives Fn by a few frames.
    @Test func commandModeHotkeyLeftoverIsDetected() {
        #expect(ModifierQuiescencePolicy.isQuiet([.maskControl, .maskCommand]) == false)
    }
}

struct AccessibilityWriteVerificationTests {
    /// The rule that stops a same-length replacement from being read as a failed paste and
    /// then "recovered" by a second insertion.
    @Test func aSameLengthReplacementIsNotObservable() {
        #expect(AccessibilityWriteVerification.isObservable(replacedLength: 12, insertedLength: 12) == false)
        #expect(AccessibilityWriteVerification.isObservable(replacedLength: 0, insertedLength: 12))
        #expect(AccessibilityWriteVerification.isObservable(replacedLength: 12, insertedLength: 3))
    }

    @Test func aWriteThatChangedNothingIsAFailure() {
        // The Electron/web-area case: the set returns .success and the field never changes.
        #expect(
            AccessibilityWriteVerification.succeeded(
                charactersBefore: 40,
                charactersAfter: 40,
                replacedLength: 0,
                insertedLength: 12
            ) == false
        )
    }

    @Test func insertingAtTheCaretGrowsTheField() {
        #expect(
            AccessibilityWriteVerification.succeeded(
                charactersBefore: 40,
                charactersAfter: 52,
                replacedLength: 0,
                insertedLength: 12
            )
        )
    }

    @Test func replacingALongerSelectionShrinksTheField() {
        #expect(
            AccessibilityWriteVerification.succeeded(
                charactersBefore: 40,
                charactersAfter: 34,
                replacedLength: 8,
                insertedLength: 2
            )
        )
    }

    /// A same-length replacement is indistinguishable from a no-op, and guessing "failed"
    /// there would paste the transcript in a second time on top of a successful write.
    @Test func sameLengthReplacementIsTrusted() {
        #expect(
            AccessibilityWriteVerification.succeeded(
                charactersBefore: 40,
                charactersAfter: 40,
                replacedLength: 5,
                insertedLength: 5
            )
        )
    }
}

@MainActor
struct ClipboardTransactionTests {
    private func makePasteboard(_ name: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MurmurTests.\(name).\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    @Test func restoresWhatTheUserHadOnTheClipboard() {
        let pasteboard = makePasteboard("restore")
        pasteboard.clearContents()
        pasteboard.setString("user copy", forType: .string)

        let transaction = ClipboardTransaction(pasteboard: pasteboard)
        #expect(transaction.write("dictated text"))
        #expect(pasteboard.string(forType: .string) == "dictated text")

        transaction.restoreIfUntouched()
        #expect(pasteboard.string(forType: .string) == "user copy")
    }

    @Test func marksTheInjectedItemTransientSoClipboardManagersSkipIt() {
        let pasteboard = makePasteboard("transient")
        let transaction = ClipboardTransaction(pasteboard: pasteboard)
        #expect(transaction.write("dictated text"))
        #expect(pasteboard.types?.contains(PasteboardConvention.transient) == true)
    }

    @Test func doesNotOverwriteACopyTheUserMadeWhileWaiting() {
        let pasteboard = makePasteboard("usercopy")
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)

        let transaction = ClipboardTransaction(pasteboard: pasteboard)
        #expect(transaction.write("dictated text"))
        pasteboard.clearContents()
        pasteboard.setString("something the user copied", forType: .string)

        transaction.restoreIfUntouched()
        #expect(pasteboard.string(forType: .string) == "something the user copied")
    }

    /// A copy made between the two dictations is newer than the first archive, so it — not
    /// the clipboard from before dictation 1 — is what the user gets back.
    @Test func aCopyBetweenTwoDictationsSurvivesBoth() {
        let pasteboard = makePasteboard("interleaved")
        pasteboard.clearContents()
        pasteboard.setString("older copy", forType: .string)

        let transaction = ClipboardTransaction(pasteboard: pasteboard)
        #expect(transaction.write("first transcript"))
        transaction.scheduleRestore(after: .seconds(30))

        pasteboard.clearContents()
        pasteboard.setString("copied between dictations", forType: .string)

        #expect(transaction.write("second transcript"))
        transaction.restoreIfUntouched()
        #expect(pasteboard.string(forType: .string) == "copied between dictations")
    }

    /// Two dictations in quick succession: archiving again would capture Murmur's own
    /// injected text and hand it back to the user as their clipboard.
    @Test func overlappingTransactionsKeepTheOriginalArchive() {
        let pasteboard = makePasteboard("overlap")
        pasteboard.clearContents()
        pasteboard.setString("user copy", forType: .string)

        let transaction = ClipboardTransaction(pasteboard: pasteboard)
        #expect(transaction.write("first transcript"))
        transaction.scheduleRestore(after: .seconds(30))
        #expect(transaction.write("second transcript"))
        #expect(pasteboard.string(forType: .string) == "second transcript")

        transaction.restoreIfUntouched()
        #expect(pasteboard.string(forType: .string) == "user copy")
    }

    @Test func abandonLeavesTheTranscriptReachableWithCommandV() {
        let pasteboard = makePasteboard("abandon")
        pasteboard.clearContents()
        pasteboard.setString("user copy", forType: .string)

        let transaction = ClipboardTransaction(pasteboard: pasteboard)
        #expect(transaction.write("transcript that could not be inserted"))
        transaction.abandon()
        transaction.restoreIfUntouched()

        #expect(pasteboard.string(forType: .string) == "transcript that could not be inserted")
    }

    @Test func aScheduledRestoreEventuallyHandsTheClipboardBack() async throws {
        let pasteboard = makePasteboard("scheduled")
        pasteboard.clearContents()
        pasteboard.setString("user copy", forType: .string)

        let transaction = ClipboardTransaction(pasteboard: pasteboard)
        #expect(transaction.write("dictated text"))
        transaction.scheduleRestore(after: .milliseconds(20))
        #expect(pasteboard.string(forType: .string) == "dictated text")

        let restored = await waitUntil { pasteboard.string(forType: .string) == "user copy" }
        #expect(restored)
    }
}
