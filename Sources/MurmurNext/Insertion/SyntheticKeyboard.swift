import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Resolves virtual key codes through the *active* keyboard layout.
///
/// A hardcoded ANSI code is only correct on QWERTY. Cocoa matches key equivalents against
/// the character a layout produces for a code, so posting code 9 as "v" types ⌘K on Dvorak
/// and pastes nothing. The lookup is deliberately not cached — the user can switch layout
/// between two dictations and a stale answer is the exact bug this type exists to remove.
///
/// Main actor because Text Input Services is main-thread only: `TISCopyCurrent…` does not
/// fail off the main thread, it calls `abort()`.
@MainActor
enum KeyboardLayoutKeyCodes {
    static func keyCode(for character: Character) -> CGKeyCode? {
        guard let layoutData = currentLayoutData() else { return nil }
        return layoutData.withUnsafeBytes { raw -> CGKeyCode? in
            guard let base = raw.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            let target = String(character)
            return (CGKeyCode(0)...CGKeyCode(127)).first { code in
                KeyboardLayoutKeyCodes.character(forKeyCode: code, layout: layout) == target
            }
        }
    }

    private static func character(
        forKeyCode keyCode: CGKeyCode,
        layout: UnsafePointer<UCKeyboardLayout>
    ) -> String? {
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    private static func currentLayoutData() -> Data? {
        if let data = layoutData(from: TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()) {
            return data
        }
        // Input methods (Japanese, Pinyin, …) expose no Unicode layout of their own; the
        // ASCII-capable layout underneath them is what ⌘-shortcuts resolve against.
        return layoutData(from: TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue())
    }

    private static func layoutData(from source: TISInputSource?) -> Data? {
        guard let source,
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }
}

/// Which physically-held modifiers would corrupt a synthetic key equivalent.
///
/// The window server ORs the real modifier state into events posted at the HID level, so a
/// modifier the user has not let go of yet turns ⌘V into some other shortcut. Command is
/// excluded: for ⌘V it is the flag being asked for anyway.
enum ModifierQuiescencePolicy {
    static let interfering: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn,
    ]

    static func contamination(in flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(interfering)
    }

    static func isQuiet(_ flags: CGEventFlags) -> Bool {
        contamination(in: flags).isEmpty
    }
}

/// Posts the keystrokes Murmur needs to drive another application.
///
/// Main actor because the layout lookup behind ⌘V is (see `KeyboardLayoutKeyCodes`).
@MainActor
enum SyntheticKeyboard {
    /// Return. Non-character keys are layout-independent, so this one is safe to hardcode.
    static let returnKeyCode: CGKeyCode = 36

    private static let quiescencePollInterval = Duration.milliseconds(20)

    static func currentModifierFlags() -> CGEventFlags {
        CGEventSource.flagsState(.combinedSessionState)
    }

    /// Waits for the user's hand to come off the modifier keys, up to `timeout`.
    ///
    /// Murmur's hotkey is Fn (Ctrl+Fn in command mode) and insertion happens on release, so
    /// there is normally nothing to wait for — but Ctrl outlives Fn often enough that
    /// skipping this drops the paste in command mode.
    static func waitForModifierQuiescence(timeout: Duration) async {
        guard ModifierQuiescencePolicy.isQuiet(currentModifierFlags()) == false else { return }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: quiescencePollInterval)
            if ModifierQuiescencePolicy.isQuiet(currentModifierFlags()) { return }
        }
    }

    /// Posts ⌘V for the current keyboard layout.
    ///
    /// Delivery is at the HID tap rather than `postToPid`: apps that do not take events off
    /// the standard path — Electron above all — ignore per-process posts, and the caller has
    /// already confirmed the target is frontmost.
    static func postPaste() throws {
        guard let keyCode = KeyboardLayoutKeyCodes.keyCode(for: "v") else {
            throw TextInsertionError.eventPostingUnavailable
        }
        try post(keyCode: keyCode, flags: .maskCommand)
    }

    static func postReturn() throws {
        try post(keyCode: returnKeyCode, flags: [])
    }

    private static func post(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        // A private source carries no modifier state of its own, so the flags set below are
        // the only ones this event contributes.
        guard let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { throw TextInsertionError.eventPostingUnavailable }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
