import AppKit
import ApplicationServices
import Foundation

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

enum ClipboardTransactionPolicy {
    static func shouldRestore(injectedChangeCount: Int, currentChangeCount: Int) -> Bool {
        injectedChangeCount == currentChangeCount
    }
}

enum TextInsertionError: Error, LocalizedError {
    case accessibilityPermissionMissing
    case noFocusedApplication
    case noEditableTarget
    case targetChanged
    case accessibilityFailure(AXError)
    case clipboardFailure

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing: "Accessibility permission is required to insert dictated text."
        case .noFocusedApplication: "Murmur could not identify the application you were writing in."
        case .noEditableTarget: "The focused control does not accept dictated text."
        case .targetChanged: "The focused application changed before Murmur could insert the transcript."
        case .accessibilityFailure(let error): "macOS rejected text insertion (\(error.rawValue))."
        case .clipboardFailure: "Murmur could not use the clipboard insertion fallback."
        }
    }
}

struct ApplicationContextClassifier: Sendable {
    func classify(bundleIdentifier: String, applicationName: String) -> WritingContext {
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
    func captureTarget() throws -> CapturedTextTarget
    func insert(_ text: String, into target: CapturedTextTarget) async throws -> TextInsertionOutcome
    func selectedText(in target: CapturedTextTarget) -> String?
    func pressEnter(in target: CapturedTextTarget) throws
}

@MainActor
final class CapturedTextTarget {
    let descriptor: TargetApplicationDescriptor
    fileprivate let element: AXUIElement?

    init(descriptor: TargetApplicationDescriptor, element: AXUIElement? = nil) {
        self.descriptor = descriptor
        self.element = element
    }
}

@MainActor
final class TextInsertionCoordinator: TextInsertionServicing {
    private let classifier = ApplicationContextClassifier()

    func captureTarget() throws -> CapturedTextTarget {
        guard AXIsProcessTrusted() else { throw TextInsertionError.accessibilityPermissionMissing }
        guard let application = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = application.bundleIdentifier,
              let localizedName = application.localizedName
        else { throw TextInsertionError.noFocusedApplication }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard result == .success, let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { throw TextInsertionError.noEditableTarget }

        let descriptor = TargetApplicationDescriptor(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            localizedName: localizedName,
            writingContext: classifier.classify(bundleIdentifier: bundleIdentifier, applicationName: localizedName)
        )
        return CapturedTextTarget(
            descriptor: descriptor,
            element: unsafeDowncast(focusedValue, to: AXUIElement.self)
        )
    }

    func insert(_ text: String, into target: CapturedTextTarget) async throws -> TextInsertionOutcome {
        guard text.isEmpty == false else { throw TextInsertionError.noEditableTarget }
        guard let element = target.element else { throw TextInsertionError.noEditableTarget }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.descriptor.processIdentifier else {
            throw TextInsertionError.targetChanged
        }

        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        )
        if settableResult == .success, isSettable.boolValue {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            if result == .success {
                return TextInsertionOutcome(method: .accessibility, message: "Inserted with Accessibility")
            }
        }

        return try await pasteUsingClipboard(text, processIdentifier: target.descriptor.processIdentifier)
    }

    func selectedText(in target: CapturedTextTarget) -> String? {
        guard let element = target.element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    func pressEnter(in target: CapturedTextTarget) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.descriptor.processIdentifier else {
            throw TextInsertionError.targetChanged
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        else { throw TextInsertionError.accessibilityFailure(.failure) }
        keyDown.postToPid(target.descriptor.processIdentifier)
        keyUp.postToPid(target.descriptor.processIdentifier)
    }

    private func pasteUsingClipboard(_ text: String, processIdentifier: pid_t) async throws -> TextInsertionOutcome {
        let pasteboard = NSPasteboard.general
        let archive = PasteboardArchive(pasteboard: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            archive.restore(to: pasteboard)
            throw TextInsertionError.clipboardFailure
        }
        let injectedChangeCount = pasteboard.changeCount

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier else {
            archive.restore(to: pasteboard)
            throw TextInsertionError.targetChanged
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            archive.restore(to: pasteboard)
            throw TextInsertionError.clipboardFailure
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        try await Task.sleep(for: .milliseconds(140))
        if ClipboardTransactionPolicy.shouldRestore(
            injectedChangeCount: injectedChangeCount,
            currentChangeCount: pasteboard.changeCount
        ) {
            archive.restore(to: pasteboard)
        }
        return TextInsertionOutcome(method: .clipboard, message: "Inserted with clipboard fallback")
    }
}

@MainActor
private struct PasteboardArchive {
    private struct Item {
        let values: [(NSPasteboard.PasteboardType, Data)]
    }

    private let items: [Item]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Item(values: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { archived -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in archived.values {
                item.setData(data, forType: type)
            }
            return item
        }
        if restoredItems.isEmpty == false {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
