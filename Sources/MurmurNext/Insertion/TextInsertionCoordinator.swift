import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import OSLog

struct TargetApplicationDescriptor: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let localizedName: String
    let writingContext: WritingContext
}

struct TextInsertionOutcome: Equatable, Sendable {
    enum Method: String, Equatable, Sendable {
        case accessibility
        case clipboard
    }

    let method: Method
    let message: String
}

enum TextInsertionError: Error, LocalizedError {
    case accessibilityPermissionMissing
    case noFocusedApplication
    case emptyTranscript
    case targetChanged
    case secureInputActive
    case eventPostingUnavailable
    case pasteRejected
    case accessibilityFailure(AXError)
    case clipboardFailure

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility permission is required to insert dictated text."
        case .noFocusedApplication:
            "Murmur could not identify the application you were writing in."
        case .emptyTranscript:
            "There was nothing to insert."
        case .targetChanged:
            "The focused application changed, so the transcript was left on your clipboard — press ⌘V to insert it."
        case .secureInputActive:
            "Secure input is active, so macOS blocks keystrokes from other apps. The transcript is on your clipboard — press ⌘V to insert it."
        case .eventPostingUnavailable:
            "Murmur could not send a paste keystroke. The transcript is on your clipboard — press ⌘V to insert it."
        case .pasteRejected:
            "The app did not accept the pasted transcript. It is on your clipboard — press ⌘V to insert it."
        case .accessibilityFailure(let error):
            "macOS rejected text insertion (\(error.rawValue))."
        case .clipboardFailure:
            "Murmur could not insert the transcript, and could not copy it to the clipboard either."
        }
    }

    /// Two or three words for the Flow Bar. The bar sets its legend in tracked caps,
    /// which is a legend voice: it carries a label, never a sentence. The full
    /// `errorDescription` still goes to the Hub, where there is room to read it.
    var flowBarLabel: String {
        switch self {
        case .accessibilityPermissionMissing: "Needs access"
        case .noFocusedApplication: "No target"
        case .emptyTranscript: "Nothing to write"
        case .targetChanged, .secureInputActive, .eventPostingUnavailable, .pasteRejected:
            "On clipboard"
        case .accessibilityFailure: "Write failed"
        case .clipboardFailure: "Not saved"
        }
    }

    /// The one action that recovers this fault, or nothing when there is none.
    var flowBarRecovery: String? {
        switch self {
        case .targetChanged, .secureInputActive, .eventPostingUnavailable, .pasteRejected:
            "⌘V to paste"
        default:
            nil
        }
    }
}

struct ApplicationContextClassifier: Sendable {
    func classify(
        bundleIdentifier: String,
        applicationName: String,
        activeBrowserURL: URL? = nil,
        browserDomainDetectionAllowed: Bool = false
    ) -> WritingContext {
        let fingerprint = "\(bundleIdentifier) \(applicationName)".lowercased()

        if containsAny(fingerprint, ["terminal", "iterm", "warp", "kitty", "alacritty", "wezterm"]) {
            return .terminal
        }
        if containsAny(fingerprint, ["cursor", "windsurf", "xcode", "visual studio code", "vscode", "zed"]) {
            return .code
        }
        if containsAny(fingerprint, ["mail", "outlook", "superhuman", "spark"]) {
            return .email
        }
        if containsAny(fingerprint, ["slack", "messages", "discord", "signal", "whatsapp", "telegram", "teams"]) {
            return .messaging
        }
        if containsAny(fingerprint, ["safari", "chrome", "firefox", "browser", "arc", "brave", "edge"]) {
            if let contextual = BrowserDomainContext().writingContext(
                bundleIdentifier: bundleIdentifier,
                activeURL: activeBrowserURL,
                permissionGranted: browserDomainDetectionAllowed
            ) {
                return contextual
            }
            return .browser
        }
        if containsAny(fingerprint, ["word", "pages", "notes", "notion", "obsidian", "textedit", "bear"]) {
            return .document
        }
        return .general
    }

    private func containsAny(_ source: String, _ needles: [String]) -> Bool {
        needles.contains(where: source.contains)
    }
}

@MainActor
protocol TextInsertionServicing: AnyObject {
    func captureTarget(browserDomainDetectionAllowed: Bool) throws -> CapturedTextTarget
    func insert(_ text: String, into target: CapturedTextTarget) async throws -> TextInsertionOutcome
    func selectedText(in target: CapturedTextTarget) -> String?
    func pressEnter(in target: CapturedTextTarget) async throws
}

@MainActor
final class CapturedTextTarget {
    let descriptor: TargetApplicationDescriptor
    /// The focused control, when Accessibility would tell us. Insertion does not depend on
    /// it — a nil element only rules out the Accessibility fallback and reading a selection.
    fileprivate let element: AXUIElement?

    init(descriptor: TargetApplicationDescriptor, element: AXUIElement? = nil) {
        self.descriptor = descriptor
        self.element = element
    }
}

/// Puts dictated text into whatever the user was writing in.
///
/// Insertion goes through the clipboard rather than through Accessibility, even though
/// Accessibility looks like the tidier option. `AXSelectedText` only works in native AppKit
/// text controls: Chromium and Electron hosts — Slack, Discord, VS Code, Notion, Chrome, Arc,
/// every web text field — advertise the attribute as settable, return `.success`, and then
/// either do nothing or write text the app's own model never sees. A synthetic ⌘V goes
/// through the same input path as the user's own paste, so it works everywhere the user can
/// type. Accessibility stays as the fallback for when keystrokes cannot be delivered at all.
@MainActor
final class TextInsertionCoordinator: TextInsertionServicing {
    private static let logger = Logger(subsystem: "Murmur", category: "Insertion")

    /// How long the target application gets to read the pasteboard before the user's own
    /// clipboard goes back. Costs nothing perceptible: the restore is detached.
    private static let clipboardRestoreDelay = Duration.milliseconds(600)
    /// A modifier still held from the hotkey gets OR'd into the synthetic ⌘V and turns it
    /// into a different shortcut, so give the user's hand a moment to come off the keys.
    private static let modifierQuiescenceTimeout = Duration.milliseconds(250)
    /// How long to watch the focused control for the pasted text to appear before deciding
    /// the app ignored the keystroke.
    private static let pasteVerificationTimeout = Duration.milliseconds(500)
    private static let pasteVerificationPollInterval = Duration.milliseconds(20)

    private let classifier = ApplicationContextClassifier()
    private let clipboard: ClipboardTransaction
    private let browserURLReader: any BrowserActiveURLReading

    init(
        clipboard: ClipboardTransaction = ClipboardTransaction(),
        browserURLReader: any BrowserActiveURLReading = AccessibilityBrowserActiveURLReader()
    ) {
        self.clipboard = clipboard
        self.browserURLReader = browserURLReader
    }

    func captureTarget(browserDomainDetectionAllowed: Bool) throws -> CapturedTextTarget {
        guard AXIsProcessTrusted() else { throw TextInsertionError.accessibilityPermissionMissing }
        guard let application = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = application.bundleIdentifier,
              let localizedName = application.localizedName
        else { throw TextInsertionError.noFocusedApplication }

        // Read browser context only after explicit permission and keep only the resulting
        // category. The URL itself is never returned, stored, logged, or transmitted.
        let baseContext = classifier.classify(
            bundleIdentifier: bundleIdentifier,
            applicationName: localizedName
        )
        let element = AccessibilityTextElement.focusedElement(
            processIdentifier: application.processIdentifier
        )
        let activeBrowserURL = browserDomainDetectionAllowed && baseContext == .browser
            ? browserURLReader.activeURL(
                processIdentifier: application.processIdentifier,
                focusedElement: element
            )
            : nil
        let descriptor = TargetApplicationDescriptor(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            localizedName: localizedName,
            writingContext: classifier.classify(
                bundleIdentifier: bundleIdentifier,
                applicationName: localizedName,
                activeBrowserURL: activeBrowserURL,
                browserDomainDetectionAllowed: browserDomainDetectionAllowed
            )
        )
        // An unreadable focused element must not abort the session. Plenty of apps hide
        // their focus from Accessibility, and this runs *before the user has spoken* —
        // failing here refuses to record dictation that clipboard insertion handles fine.
        if element == nil {
            Self.logger.debug(
                "No accessible focused element in \(bundleIdentifier, privacy: .public); clipboard insertion only."
            )
        }
        return CapturedTextTarget(descriptor: descriptor, element: element)
    }

    /// Inserts `text`, and guarantees that if it throws the transcript is on the clipboard.
    ///
    /// Nothing else keeps it: history is only written on success, so an insertion that fails
    /// without parking the text destroys words the user spoke.
    func insert(_ text: String, into target: CapturedTextTarget) async throws -> TextInsertionOutcome {
        guard text.isEmpty == false else { throw TextInsertionError.emptyTranscript }
        do {
            return try await attemptInsert(text, into: target)
        } catch {
            // Every error message below promises the transcript is one ⌘V away, so if the
            // clipboard itself is what failed, report *that* rather than a promise Murmur
            // cannot keep.
            guard park(text) else { throw TextInsertionError.clipboardFailure }
            throw error
        }
    }

    private func attemptInsert(
        _ text: String,
        into target: CapturedTextTarget
    ) async throws -> TextInsertionOutcome {
        try requireFrontmost(target.descriptor)

        // Secure input (password fields, terminals asking for a password, some password
        // managers) makes the window server discard synthetic keystrokes outright, so ⌘V
        // cannot work. An Accessibility write still can, and is the only path left.
        if IsSecureEventInputEnabled() {
            Self.logger.notice("Secure input active; using the Accessibility path instead of ⌘V.")
            return try insertUsingAccessibility(text, into: target, otherwise: .secureInputActive)
        }

        guard clipboard.write(text) else {
            return try insertUsingAccessibility(text, into: target, otherwise: .clipboardFailure)
        }

        await SyntheticKeyboard.waitForModifierQuiescence(timeout: Self.modifierQuiescenceTimeout)
        let heldModifiers = ModifierQuiescencePolicy.contamination(in: SyntheticKeyboard.currentModifierFlags())
        if heldModifiers.isEmpty == false {
            Self.logger.notice(
                "Pasting with modifiers still held (\(heldModifiers.rawValue, privacy: .public)); the target app may ignore it."
            )
        }

        // Re-checked after the wait: pasting a transcript into whatever the user switched to
        // is worse than not inserting it.
        try requireFrontmost(target.descriptor)
        let verifier = AccessibilityPasteVerifier(
            processIdentifier: target.descriptor.processIdentifier,
            insertedLength: text.utf16.count
        )
        try SyntheticKeyboard.postPaste()

        switch await verifier.confirm(
            timeout: Self.pasteVerificationTimeout,
            pollInterval: Self.pasteVerificationPollInterval
        ) {
        case .confirmed, .unverifiable:
            clipboard.scheduleRestore(after: Self.clipboardRestoreDelay)
            return TextInsertionOutcome(method: .clipboard, message: "Inserted with clipboard paste")
        case .rejected:
            Self.logger.error(
                "Paste keystroke was ignored by \(target.descriptor.bundleIdentifier, privacy: .public)."
            )
            // Take the transcript back off the clipboard *before* trying anything else: a
            // target that pastes later than the verification budget would otherwise insert
            // it a second time, on top of the Accessibility write below.
            clipboard.restoreIfUntouched()
            // That write goes to the control directly, so it is worth one try in the apps
            // that swallow synthetic keystrokes. A throw here re-parks the transcript on the
            // clipboard, which is what `insert` promises.
            return try insertUsingAccessibility(text, into: target, otherwise: .pasteRejected)
        }
    }

    func selectedText(in target: CapturedTextTarget) -> String? {
        guard let element = currentElement(for: target) else { return nil }
        return AccessibilityTextElement.selectedText(of: element)
    }

    func pressEnter(in target: CapturedTextTarget) async throws {
        try requireFrontmost(target.descriptor)
        // Shift+Return means "newline, do not send" in most messaging apps, so a held
        // modifier changes the meaning of this keystroke rather than just breaking it.
        await SyntheticKeyboard.waitForModifierQuiescence(timeout: Self.modifierQuiescenceTimeout)
        try requireFrontmost(target.descriptor)
        try SyntheticKeyboard.postReturn()
    }

    private func insertUsingAccessibility(
        _ text: String,
        into target: CapturedTextTarget,
        otherwise error: TextInsertionError
    ) throws -> TextInsertionOutcome {
        guard let element = currentElement(for: target),
              AccessibilityTextElement.replaceSelectedText(with: text, in: element)
        else { throw error }
        return TextInsertionOutcome(method: .accessibility, message: "Inserted with Accessibility")
    }

    /// Where the user is writing *now*.
    ///
    /// The element captured when they started speaking is only a fallback: clicking into
    /// another field mid-sentence is ordinary behaviour, a paste follows focus, and an
    /// Accessibility write through the stale element would land in the field they left.
    private func currentElement(for target: CapturedTextTarget) -> AXUIElement? {
        AccessibilityTextElement.focusedElement(processIdentifier: target.descriptor.processIdentifier)
            ?? target.element
    }

    /// Leaves the transcript on the clipboard, with no restore scheduled over it, so words
    /// Murmur could not insert are one ⌘V away rather than gone.
    private func park(_ text: String) -> Bool {
        let written = clipboard.write(text)
        if written == false {
            Self.logger.error("Could not put the transcript on the clipboard; it cannot be recovered.")
        }
        clipboard.abandon()
        return written
    }

    private func requireFrontmost(_ descriptor: TargetApplicationDescriptor) throws {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            throw TextInsertionError.noFocusedApplication
        }
        // Bundle identifier as well as pid: an app that relaunched, or that fronts a helper
        // process, is still the application the user was writing in.
        guard frontmost.processIdentifier == descriptor.processIdentifier
            || frontmost.bundleIdentifier == descriptor.bundleIdentifier
        else { throw TextInsertionError.targetChanged }
    }
}
