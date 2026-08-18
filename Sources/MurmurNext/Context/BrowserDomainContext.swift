import ApplicationServices
import Foundation

struct BrowserDomainContext: Sendable {
    static let supportedBundleIdentifiers: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "com.brave.browser",
        "com.microsoft.edgemac",
        "company.thebrowser.browser",
        "org.mozilla.firefox",
        "org.chromium.chromium",
    ]

    func writingContext(
        bundleIdentifier: String,
        activeURL: URL?,
        permissionGranted: Bool
    ) -> WritingContext? {
        guard permissionGranted,
              Self.supportedBundleIdentifiers.contains(bundleIdentifier.lowercased()),
              let activeURL,
              activeURL.scheme?.lowercased() == "https",
              var host = activeURL.host?.lowercased()
        else {
            return nil
        }
        if host.hasSuffix(".") {
            host.removeLast()
        }
        guard host == "mail.google.com" else { return nil }
        return .email
    }
}

@MainActor
protocol BrowserActiveURLReading: AnyObject {
    func activeURL(processIdentifier: pid_t, focusedElement: AXUIElement?) -> URL?
}

@MainActor
final class AccessibilityBrowserActiveURLReader: BrowserActiveURLReading {
    private static let maximumAncestorDepth = 16

    func activeURL(processIdentifier: pid_t, focusedElement: AXUIElement?) -> URL? {
        var element = focusedElement
        for _ in 0..<Self.maximumAncestorDepth {
            guard let current = element else { break }
            if let url = urlAttribute(from: current) { return url }
            element = elementAttribute(kAXParentAttribute as CFString, from: current)
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        if let focusedWindow = elementAttribute(kAXFocusedWindowAttribute as CFString, from: application) {
            return urlAttribute(from: focusedWindow)
        }
        return nil
    }

    private func urlAttribute(from element: AXUIElement) -> URL? {
        for attribute in [kAXURLAttribute as CFString, kAXDocumentAttribute as CFString] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
                  let value
            else {
                continue
            }
            if let url = value as? URL { return url }
            if let string = value as? String, let url = URL(string: string) { return url }
        }
        return nil
    }

    private func elementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
