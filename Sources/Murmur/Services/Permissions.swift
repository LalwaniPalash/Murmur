import AppKit
import AVFoundation
import Foundation
import Speech

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var permissions: AppPermissions = .unknown
    @Published private(set) var isRequestingAccess = false
    private var monitorTask: Task<Void, Never>?

    deinit {
        monitorTask?.cancel()
    }

    func refresh() {
        permissions = AppPermissions(
            microphoneGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            speechRecognitionGranted: SFSpeechRecognizer.authorizationStatus() == .authorized,
            accessibilityGranted: AXIsProcessTrusted()
        )
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }

        monitorTask = Task { [weak self] in
            guard let self else { return }

            while Task.isCancelled == false {
                self.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func requestMicrophoneAccess() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    func requestSpeechAccess() async {
        _ = await Self.requestSpeechAuthorization()
        refresh()
    }

    func requestAccessibilityAccess(prompt: Bool = true) {
        guard permissions.accessibilityGranted == false else {
            refresh()
            return
        }
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func requestMissingPermissions() async {
        guard isRequestingAccess == false else { return }
        isRequestingAccess = true
        defer {
            refresh()
            isRequestingAccess = false
        }

        refresh()

        if permissions.microphoneGranted == false {
            await requestMicrophoneAccess()
        }

        if permissions.speechRecognitionGranted == false {
            await requestSpeechAccess()
        }

        if permissions.accessibilityGranted == false {
            requestAccessibilityAccess(prompt: true)
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    // SFSpeechRecognizer may invoke its completion on a background queue. Keep
    // the callback out of the MainActor-isolated closure path and hop back only
    // after the continuation resumes.
    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { authorization in
                continuation.resume(returning: authorization)
            }
        }
    }
}
