import AppKit
import Foundation

@MainActor
final class GlobalShortcutMonitor {
    var onPushToTalkPressed: (() -> Void)?
    var onPushToTalkReleased: (() -> Void)?
    var onHandsFreeToggle: (() -> Void)?
    var onCommandPressed: (() -> Void)?
    var onCommandReleased: (() -> Void)?

    private var monitorTokens: [Any] = []
    private var pendingPushStart: Task<Void, Never>?
    private var pushActive = false
    private var commandActive = false

    func start() {
        guard monitorTokens.isEmpty else { return }

        let globalFlags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
        let localFlags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
        let globalKeyDown = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
        }
        let localKeyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
            return event
        }

        [globalFlags, localFlags, globalKeyDown, localKeyDown].forEach { token in
            if let token {
                monitorTokens.append(token)
            }
        }
    }

    func stop() {
        monitorTokens.forEach(NSEvent.removeMonitor)
        monitorTokens.removeAll()
        pendingPushStart?.cancel()
        pendingPushStart = nil
        pushActive = false
        commandActive = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let controlOption = flags.contains(.control) && flags.contains(.option)
        let commandChord = controlOption && flags.contains(.command)

        if commandChord {
            cancelPendingPush()
            if pushActive {
                pushActive = false
                onPushToTalkReleased?()
            }
            if !commandActive {
                commandActive = true
                onCommandPressed?()
            }
            return
        }

        if commandActive && !flags.contains(.command) {
            commandActive = false
            onCommandReleased?()
        }

        if controlOption {
            schedulePushStartIfNeeded()
        } else {
            cancelPendingPush()
            if pushActive {
                pushActive = false
                onPushToTalkReleased?()
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isHandsFreeChord = event.keyCode == 49 && flags.contains(.control) && flags.contains(.option)
        if isHandsFreeChord {
            cancelPendingPush()
            if pushActive {
                pushActive = false
                onPushToTalkReleased?()
            }
            onHandsFreeToggle?()
        }
    }

    private func schedulePushStartIfNeeded() {
        guard !pushActive, !commandActive, pendingPushStart == nil else { return }
        pendingPushStart = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, !self.commandActive else { return }
            self.pushActive = true
            self.pendingPushStart = nil
            self.onPushToTalkPressed?()
        }
    }

    private func cancelPendingPush() {
        pendingPushStart?.cancel()
        pendingPushStart = nil
    }
}
