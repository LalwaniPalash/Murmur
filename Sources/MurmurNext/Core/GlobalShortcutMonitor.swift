import ApplicationServices
import Foundation

@MainActor
final class GlobalShortcutMonitor {
    var onDictationPressed: (() -> Void)?
    var onDictationReleased: (() -> Void)?
    var onCommandPressed: (() -> Void)?
    var onCommandReleased: (() -> Void)?
    var onCancel: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var functionKeyIsDown = false
    private var activeMode: DictationMode?

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
        functionKeyIsDown = false
        activeMode = nil
    }

    private func handle(typeRawValue: UInt32, flagsRawValue: UInt64, keyCode: Int64) {
        guard let type = CGEventType(rawValue: typeRawValue) else { return }
        if type == .keyDown, keyCode == 53 {
            onCancel?()
            return
        }
        guard type == .flagsChanged else { return }

        let flags = CGEventFlags(rawValue: flagsRawValue)
        let functionIsDown = flags.contains(.maskSecondaryFn)
        if functionIsDown, functionKeyIsDown == false {
            functionKeyIsDown = true
            if flags.contains(.maskControl) {
                activeMode = .command
                onCommandPressed?()
            } else {
                activeMode = .pushToTalk
                onDictationPressed?()
            }
        } else if functionIsDown == false, functionKeyIsDown {
            functionKeyIsDown = false
            let endingMode = activeMode
            activeMode = nil
            if endingMode == .command {
                onCommandReleased?()
            } else {
                onDictationReleased?()
            }
        }
    }

    private nonisolated static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let typeRawValue = type.rawValue
        let flagsRawValue = event.flags.rawValue
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        Task { @MainActor in
            monitor.handle(typeRawValue: typeRawValue, flagsRawValue: flagsRawValue, keyCode: keyCode)
        }
        return Unmanaged.passUnretained(event)
    }
}
