import ApplicationServices
import Foundation

@MainActor
final class GlobalShortcutMonitor {
    var onDictationPressed: (() -> Void)?
    var onDictationReleased: (() -> Void)?
    var onCommandPressed: (() -> Void)?
    var onCommandUpgrade: (() -> Bool)?
    var onCommandReleased: (() -> Void)?
    var onCancel: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var chord = ShortcutChordResolver()

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        let eventMask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        let reference = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: Self.eventCallback,
            userInfo: reference
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        chord.reset()
    }

    private func handle(typeRawValue: UInt32, flagsRawValue: UInt64, keyCode: Int64) {
        guard let type = CGEventType(rawValue: typeRawValue) else { return }
        if type == .keyDown, keyCode == 53 {
            onCancel?()
            return
        }
        guard type == .flagsChanged else { return }

        let flags = CGEventFlags(rawValue: flagsRawValue)
        let actions = chord.observe(
            functionIsDown: flags.contains(.maskSecondaryFn),
            controlIsDown: flags.contains(.maskControl),
            nowNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        for action in actions {
            switch action {
            case .beginDictation:
                onDictationPressed?()
            case .beginCommand:
                onCommandPressed?()
            case .requestCommandUpgrade:
                if onCommandUpgrade?() == true {
                    chord.confirmCommandUpgrade()
                }
            case .endDictation:
                onDictationReleased?()
            case .endCommand:
                onCommandReleased?()
            }
        }
    }

    private nonisolated static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let typeRawValue = type.rawValue
        let flagsRawValue = event.flags.rawValue
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // The tap is installed on the main run loop, so handle synchronously. Spawning one
        // Task per flags event can reorder Fn and Control before the monitor sees them.
        MainActor.assumeIsolated {
            monitor.handle(typeRawValue: typeRawValue, flagsRawValue: flagsRawValue, keyCode: keyCode)
        }
        return Unmanaged.passUnretained(event)
    }
}

struct ShortcutChordResolver: Sendable {
    enum Action: Equatable, Sendable {
        case beginDictation
        case beginCommand
        case requestCommandUpgrade
        case endDictation
        case endCommand
    }

    private(set) var functionIsDown = false
    private(set) var activeMode: DictationMode?
    private var upgradeWasRequested = false

    mutating func observe(
        functionIsDown: Bool,
        controlIsDown: Bool,
        nowNanoseconds: UInt64
    ) -> [Action] {
        if functionIsDown, self.functionIsDown == false {
            self.functionIsDown = true
            upgradeWasRequested = false
            if controlIsDown {
                activeMode = .command
                return [.beginCommand]
            }
            activeMode = .pushToTalk
            return [.beginDictation]
        }

        if functionIsDown,
           self.functionIsDown,
           controlIsDown,
           activeMode == .pushToTalk,
           upgradeWasRequested == false
        {
            upgradeWasRequested = true
            return [.requestCommandUpgrade]
        }

        if functionIsDown == false, self.functionIsDown {
            self.functionIsDown = false
            upgradeWasRequested = false
            let endingMode = activeMode
            activeMode = nil
            return endingMode == .command ? [.endCommand] : [.endDictation]
        }

        return []
    }

    mutating func confirmCommandUpgrade() {
        guard functionIsDown, activeMode == .pushToTalk, upgradeWasRequested else { return }
        activeMode = .command
    }

    mutating func reset() {
        functionIsDown = false
        activeMode = nil
        upgradeWasRequested = false
    }
}
