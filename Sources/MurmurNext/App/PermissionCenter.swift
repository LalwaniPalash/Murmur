import AVFoundation
import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var microphoneGranted = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var isRequestingMicrophone = false

    var requiredPermissionsGranted: Bool {
        microphoneGranted && accessibilityGranted
    }

    init() {
        refresh()
    }

    func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestMicrophone() async {
        isRequestingMicrophone = true
        microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        isRequestingMicrophone = false
    }

    func requestAccessibilityPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
