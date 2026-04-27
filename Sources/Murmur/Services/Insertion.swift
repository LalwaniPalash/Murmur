import AppKit
import ApplicationServices
import Foundation

protocol InsertionTargetAdapter {
    var supportedBundleIdentifiers: Set<String> { get }
    func adapt(text: String) -> String
}

struct CompatibilityAdapterRegistry {
    private let adapters: [InsertionTargetAdapter] = [
        CursorAdapter(),
        WindsurfAdapter(),
    ]

    func adapt(text: String, for bundleIdentifier: String) -> String {
        adapters.first(where: { $0.supportedBundleIdentifiers.contains(bundleIdentifier) })?.adapt(text: text) ?? text
    }
}

final class AXInsertionCoordinator {
    private let adapterRegistry = CompatibilityAdapterRegistry()

    func selectedText() -> String? {
        guard let element = focusedElement() else {
            return nil
        }

        var selectedTextValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        guard result == .success else {
            return nil
        }

        return selectedTextValue as? String
    }

    func insertText(_ text: String, into app: FrontmostAppDescriptor) -> InsertionOutcome {
        let adapted = adapterRegistry.adapt(text: text, for: app.bundleIdentifier)
        guard let element = focusedElement() else {
            return copyToClipboard(text: adapted)
        }

        guard let currentValue = stringValue(for: element),
              let selectedRange = selectedRange(for: element) else {
            return copyToClipboard(text: adapted)
        }

        if let range = Range(NSRange(location: selectedRange.location, length: selectedRange.length), in: currentValue) {
            let updated = currentValue.replacingCharacters(in: range, with: adapted)
            let newLocation = currentValue.distance(from: currentValue.startIndex, to: range.lowerBound) + adapted.count
            if setValue(updated, for: element), setSelection(range: CFRange(location: newLocation, length: 0), for: element) {
                return InsertionOutcome(succeeded: true, method: .accessibility, message: "Inserted via Accessibility")
            }
        }

        return fallbackPaste(text: adapted)
    }

    func replaceSelectedText(with text: String, in app: FrontmostAppDescriptor) -> InsertionOutcome {
        guard let element = focusedElement(),
              let currentValue = stringValue(for: element),
              let selectedRange = selectedRange(for: element),
              let range = Range(NSRange(location: selectedRange.location, length: selectedRange.length), in: currentValue) else {
            return fallbackPaste(text: adapterRegistry.adapt(text: text, for: app.bundleIdentifier))
        }

        let adapted = adapterRegistry.adapt(text: text, for: app.bundleIdentifier)
        let updated = currentValue.replacingCharacters(in: range, with: adapted)
        let newLocation = currentValue.distance(from: currentValue.startIndex, to: range.lowerBound) + adapted.count
        guard setValue(updated, for: element), setSelection(range: CFRange(location: newLocation, length: 0), for: element) else {
            return fallbackPaste(text: adapted)
        }
        return InsertionOutcome(succeeded: true, method: .accessibility, message: "Replaced selection via Accessibility")
    }

    func floatingAnchorFrame() -> CGRect? {
        NSScreen.main?.visibleFrame
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard result == .success else {
            return nil
        }
        return focusedValue.map { unsafeDowncast($0, to: AXUIElement.self) }
    }

    private func stringValue(for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private func selectedRange(for element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard result == .success, let axValue = value else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func setValue(_ value: String, for element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef) == .success
    }

    private func setSelection(range: CFRange, for element: AXUIElement) -> Bool {
        var mutableRange = range
        guard let axValue = AXValueCreate(.cfRange, &mutableRange) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axValue) == .success
    }

    private func fallbackPaste(text: String) -> InsertionOutcome {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return InsertionOutcome(succeeded: false, method: .none, message: "Unable to create keyboard event source")
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let keyCodeV: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            snapshot.restore(to: pasteboard)
        }

        return InsertionOutcome(succeeded: true, method: .clipboard, message: "Inserted via clipboard fallback")
    }

    private func copyToClipboard(text: String) -> InsertionOutcome {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return InsertionOutcome(succeeded: true, method: .clipboard, message: "Copied to clipboard because no text input is focused")
    }
}

private struct CursorAdapter: InsertionTargetAdapter {
    let supportedBundleIdentifiers: Set<String> = ["com.todesktop.230313mzl4w4u92", "com.getcursor.Cursor"]

    func adapt(text: String) -> String {
        text.replacingOccurrences(of: #"(?i)\btag ([A-Za-z0-9_\-./]+)"#, with: "@$1", options: .regularExpression)
    }
}

private struct WindsurfAdapter: InsertionTargetAdapter {
    let supportedBundleIdentifiers: Set<String> = ["com.exafunction.windsurf"]

    func adapt(text: String) -> String {
        text.replacingOccurrences(of: #"(?i)\btag ([A-Za-z0-9_\-./]+)"#, with: "@$1", options: .regularExpression)
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for itemMap in items {
            let item = NSPasteboardItem()
            for (type, data) in itemMap {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}
