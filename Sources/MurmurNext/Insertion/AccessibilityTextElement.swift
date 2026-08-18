import ApplicationServices
import Foundation

/// Reads and writes the focused text control over the Accessibility API.
///
/// Every element gets a short messaging timeout first. The default is measured in seconds
/// and these calls run on the main actor, so one unresponsive target application would
/// otherwise freeze Murmur's own UI while it waits.
@MainActor
enum AccessibilityTextElement {
    static let messagingTimeout: Float = 0.35

    static func focusedElement(processIdentifier: pid_t) -> AXUIElement? {
        if let element = focusedElement(of: AXUIElementCreateSystemWide()) { return element }
        // Chromium/Electron hosts and apps that have not been asked for accessibility yet
        // routinely fail the system-wide query but answer the per-application one.
        return focusedElement(of: AXUIElementCreateApplication(processIdentifier))
    }

    static func selectedText(of element: AXUIElement) -> String? {
        copyAttribute(kAXSelectedTextAttribute, of: element) as? String
    }

    /// Replaces the selection — or inserts at the caret when nothing is selected.
    ///
    /// Returns `false` when the attribute is not settable, when macOS rejects the write, or
    /// when the element accepted the write and demonstrably did not change: web areas and
    /// some Electron controls report success for a no-op, and treating that as inserted is
    /// how a transcript gets dropped on the floor.
    static func replaceSelectedText(with text: String, in element: AXUIElement) -> Bool {
        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        ) == .success, isSettable.boolValue else { return false }

        let charactersBefore = numberOfCharacters(of: element)
        let replacedLength = selectedText(of: element)?.utf16.count ?? 0

        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success else { return false }

        guard let charactersBefore,
              let charactersAfter = numberOfCharacters(of: element)
        else { return true }  // Nothing to verify against; take macOS at its word.
        return AccessibilityWriteVerification.succeeded(
            charactersBefore: charactersBefore,
            charactersAfter: charactersAfter,
            replacedLength: replacedLength,
            insertedLength: text.utf16.count
        )
    }

    private static func focusedElement(of element: AXUIElement) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        guard let value = copyAttribute(kAXFocusedUIElementAttribute, of: element),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let focused = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(focused, messagingTimeout)
        return focused
    }

    static func numberOfCharacters(of element: AXUIElement) -> Int? {
        copyAttribute(kAXNumberOfCharactersAttribute, of: element) as? Int
    }

    private static func copyAttribute(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}

/// Watches the focused control to find out whether a synthetic ⌘V actually landed.
///
/// Posting the keystroke proves nothing: the window server accepts it whether or not the
/// app does anything with it. Without this, an app that ignores the paste gets reported as
/// a successful dictation and the transcript is wiped off the clipboard 600ms later — the
/// user's words end up nowhere at all.
///
/// Focus is re-read at the moment of pasting rather than reusing the element captured when
/// the user started speaking: they may have clicked into a different field in the meantime,
/// and the paste follows focus.
@MainActor
struct AccessibilityPasteVerifier {
    enum Result: Equatable {
        case confirmed
        /// The control does not report its length; the paste probably worked, but nothing
        /// here can tell. Treated as success, since claiming failure would be a lie just as
        /// often as claiming success.
        case unverifiable
        case rejected
    }

    private let element: AXUIElement?
    private let charactersBefore: Int?
    private let isObservable: Bool

    init(processIdentifier: pid_t, insertedLength: Int) {
        let element = AccessibilityTextElement.focusedElement(processIdentifier: processIdentifier)
        self.element = element
        charactersBefore = element.flatMap(AccessibilityTextElement.numberOfCharacters)
        let replacedLength = element.flatMap(AccessibilityTextElement.selectedText)?.utf16.count ?? 0
        isObservable = AccessibilityWriteVerification.isObservable(
            replacedLength: replacedLength,
            insertedLength: insertedLength
        )
    }

    func confirm(timeout: Duration, pollInterval: Duration) async -> Result {
        guard let element, let charactersBefore, isObservable else { return .unverifiable }
        let deadline = ContinuousClock.now + timeout
        repeat {
            // A control that stops answering ends the watch rather than spending the rest of
            // the budget on Accessibility timeouts, one per poll, on the main actor.
            guard let now = AccessibilityTextElement.numberOfCharacters(of: element) else {
                return .unverifiable
            }
            if now != charactersBefore { return .confirmed }
            try? await Task.sleep(for: pollInterval)
        } while ContinuousClock.now < deadline
        return .rejected
    }
}

/// Whether a character-count delta is consistent with the write having landed.
enum AccessibilityWriteVerification {
    /// Whether a character count can distinguish "the text landed" from "nothing happened".
    ///
    /// Replacing a selection with text of the same length leaves the count untouched, so the
    /// two are indistinguishable. Every caller has to treat that as *cannot tell* and assume
    /// success: guessing "failed" there runs a fallback insertion on top of a write that
    /// worked, and the user gets the transcript twice.
    static func isObservable(replacedLength: Int, insertedLength: Int) -> Bool {
        replacedLength != insertedLength
    }

    static func succeeded(
        charactersBefore: Int,
        charactersAfter: Int,
        replacedLength: Int,
        insertedLength: Int
    ) -> Bool {
        guard isObservable(replacedLength: replacedLength, insertedLength: insertedLength) else {
            return true
        }
        return charactersAfter != charactersBefore
    }
}
