import AppKit
import Combine
import SwiftUI

enum FlowBarPlacement {
    static func dockedOrigin(
        proposed: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        threshold: CGFloat = 26
    ) -> CGPoint {
        let maximumX = max(visibleFrame.maxX - panelSize.width, visibleFrame.minX)
        let maximumY = max(visibleFrame.maxY - panelSize.height, visibleFrame.minY)
        var x = min(max(proposed.x, visibleFrame.minX), maximumX)
        var y = min(max(proposed.y, visibleFrame.minY), maximumY)
        if abs(x - visibleFrame.minX) <= threshold { x = visibleFrame.minX }
        if abs(x - maximumX) <= threshold { x = maximumX }
        if abs(y - visibleFrame.minY) <= threshold { y = visibleFrame.minY }
        if abs(y - maximumY) <= threshold { y = maximumY }
        return CGPoint(x: x, y: y)
    }
}

@MainActor
final class FlowBarController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var phase: DictationPhase = .idle
    @Published private(set) var audioLevelDecibels = -96.0
    @Published private(set) var whisperLikelihood = 0.0
    @Published private(set) var message = ""
    @Published private(set) var errorRecovery: String?
    @Published private(set) var transformationNotice: String?
    @Published private(set) var showsAudioMovement = true
    @Published private(set) var allowsDocking = true

    private weak var orchestrator: DictationOrchestrator?
    private var panel: FlowBarPanel?
    private var subscriptions: Set<AnyCancellable> = []
    private var hideTask: Task<Void, Never>?

    init(orchestrator: DictationOrchestrator) {
        self.orchestrator = orchestrator
        super.init()
        orchestrator.$phase
            .sink { [weak self] phase in self?.phaseChanged(phase) }
            .store(in: &subscriptions)
        orchestrator.$audioLevelDecibels
            .sink { [weak self] in self?.audioLevelDecibels = $0 }
            .store(in: &subscriptions)
        orchestrator.$whisperLikelihood
            .sink { [weak self] in self?.whisperLikelihood = $0 }
            .store(in: &subscriptions)
        // The bar takes the short label, never the full sentence: its legend is set in
        // tracked caps, which cannot carry one.
        orchestrator.$lastErrorLabel
            .sink { [weak self] in
                if let label = $0 { self?.message = label }
            }
            .store(in: &subscriptions)
        orchestrator.$lastErrorRecovery
            .sink { [weak self] in self?.errorRecovery = $0 }
            .store(in: &subscriptions)
        orchestrator.$lastTransformationNotice
            .sink { [weak self] in self?.transformationNotice = $0 }
            .store(in: &subscriptions)
    }

    func cancel() {
        Task { await orchestrator?.cancel() }
    }

    func apply(settings: MurmurSettingsRecord) {
        showsAudioMovement = settings.showLiveAudioMovement
        allowsDocking = settings.allowFlowBarDocking
        panel?.isMovableByWindowBackground = settings.allowFlowBarDocking
    }

    private func phaseChanged(_ phase: DictationPhase) {
        self.phase = phase
        hideTask?.cancel()
        switch phase {
        case .idle:
            hide()
        case .calibrating, .listening, .finalizing, .inserting:
            message = ""
            show()
        case .completed:
            message = "Inserted"
            show()
            scheduleHide()
        case .failed:
            show()
            scheduleHide(after: .seconds(4))
        case .cancelled:
            message = "Cancelled"
            show()
            scheduleHide()
        }
    }

    private func show() {
        if panel == nil {
            let panel = FlowBarPanel()
            panel.isMovableByWindowBackground = allowsDocking
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: FlowBarView(controller: self))
            self.panel = panel
        }
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func scheduleHide(after duration: Duration = .seconds(1.4)) {
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard Task.isCancelled == false else { return }
            self?.hide()
        }
    }

    private func positionPanel() {
        guard let panel, let screen = preferredScreen else { return }
        let size = panelSize
        let frame = screen.visibleFrame
        let saved = savedOrigin(for: screen)
        let proposed = saved ?? CGPoint(x: frame.midX - size.width / 2, y: frame.minY + 22)
        let origin = FlowBarPlacement.dockedOrigin(
            proposed: proposed,
            panelSize: size,
            visibleFrame: frame
        )
        panel.setFrame(
            CGRect(origin: origin, size: size),
            display: true
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard allowsDocking, let panel, let screen = panel.screen else { return }
        let origin = FlowBarPlacement.dockedOrigin(
            proposed: panel.frame.origin,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame
        )
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        UserDefaults.standard.set([Double(origin.x), Double(origin.y)], forKey: placementKey(for: screen))
    }

    private var preferredScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }

    private func savedOrigin(for screen: NSScreen) -> CGPoint? {
        guard let values = UserDefaults.standard.array(forKey: placementKey(for: screen)) as? [Double],
              values.count == 2 else { return nil }
        return CGPoint(x: CGFloat(values[0]), y: CGFloat(values[1]))
    }

    private func placementKey(for screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return "Murmur.v2.flowBar.origin.\(number?.stringValue ?? "default")"
    }

    /// Every state shares one size, faults included. Faults now carry a short legend and
    /// one recovery action instead of a sentence, so nothing needs a bigger housing.
    private var panelSize: CGSize { CGSize(width: 246, height: 42) }
}

private final class FlowBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 142, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = true
    }
}

/// The Flow Bar is the device, not the panel: a machined status plate that floats over
/// whatever the user is actually writing in. It stays black-anodised in both appearances
/// because it has to stay legible over unknown application content, and because a real
/// recorder's status plate does not change finish with the room.
enum Device {
    static let plate = Color(red: 0.075, green: 0.078, blue: 0.070)
    static let engraved = Color.white.opacity(0.92)
    static let engravedDim = Color.white.opacity(0.55)
    static let scribe = Color.white.opacity(0.13)
}

/// The controller-bound Flow Bar. It owns no appearance of its own — it reads live state
/// and hands plain values to `FlowBarFace`, so every visual state can be rendered without
/// a running dictation.
private struct FlowBarView: View {
    @ObservedObject var controller: FlowBarController

    var body: some View {
        FlowBarFace(
            phase: controller.phase,
            decibels: controller.audioLevelDecibels,
            whisperLikelihood: controller.whisperLikelihood,
            message: controller.message,
            transformationNotice: controller.transformationNotice,
            recovery: controller.errorRecovery,
            showsMeter: controller.showsAudioMovement,
            cancel: controller.cancel
        )
    }
}

/// The Flow Bar's face, driven entirely by values. Extracted from the controller so a
/// state that is hard to provoke on demand — a fault, a cancellation — can still be put
/// on screen and reviewed.
struct FlowBarFace: View {
    let phase: DictationPhase
    var decibels: Double = -96
    var whisperLikelihood: Double = 0
    var message: String = ""
    var transformationNotice: String? = nil
    var recovery: String?
    var showsMeter: Bool = true
    var cancel: () -> Void = {}

    private var isCapturing: Bool {
        phase == .listening || phase == .calibrating
    }

    var body: some View {
        HStack(spacing: MurmurTheme.Space.medium) {
            Lamp(colour: lampColour, isLit: isLampLit, diameter: 7)
                .accessibilityHidden(true)

            Text(statusText.uppercased())
                .font(MurmurFace.legend(10.5, weight: .semibold))
                .tracking(MurmurTheme.Tracking.legend)
                .foregroundStyle(Device.engraved)
                .lineLimit(1)
                .fixedSize(horizontal: phase == .failed, vertical: false)
                .frame(width: phase == .failed ? nil : 84, alignment: .leading)

            if phase == .failed {
                Spacer(minLength: MurmurTheme.Space.small)
                // The one action that recovers the fault, in the readout voice at
                // sentence case. The full explanation stays on `lastError` for the Hub;
                // a floating bar this size cannot carry a sentence legibly.
                if let recovery {
                    Text(recovery)
                        .font(MurmurFace.readout(10.5, weight: .medium))
                        .foregroundStyle(Device.engravedDim)
                        .lineLimit(1)
                        .fixedSize()
                }
            } else {
                Spacer(minLength: MurmurTheme.Space.small)
                MeterBlock(decibels: isCapturing && showsMeter ? decibels : -96)
            }

            // Always present while capturing, never hover-gated: a floating panel cannot
            // be hovered by keyboard or VoiceOver users, and cancel must stay reachable.
            if isCapturing {
                Button { cancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Device.engravedDim)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel dictation")
            }
        }
        .padding(.horizontal, MurmurTheme.Space.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.flowBar, style: .continuous)
                .fill(Device.plate)
                .shadow(color: .black.opacity(0.32), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.flowBar, style: .continuous)
                .strokeBorder(Device.scribe, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Murmur: \(statusText)")
    }

    private var lampColour: Lamp.Colour {
        switch phase {
        case .completed: .verify
        case .failed: .caution
        default: .record
        }
    }

    /// The record lamp is lit only while audio is genuinely being captured. That is the
    /// whole promise of the product expressed as one component.
    private var isLampLit: Bool {
        switch phase {
        case .listening, .calibrating, .completed, .failed: true
        default: false
        }
    }

    private var statusText: String {
        switch phase {
        case .calibrating: "Tuning"
        case .listening: whisperLikelihood > 0.45 ? "Whisper" : "Listening"
        case .finalizing: transformationNotice ?? "Correcting"
        case .inserting: transformationNotice ?? "Writing"
        case .completed: transformationNotice ?? "Inserted"
        case .failed: message.isEmpty ? "Problem" : message
        case .cancelled: "Cancelled"
        case .idle: "Ready"
        }
    }
}

/// A fixed-scale ladder over an engraved scale. The scale is printed once and never
/// rescales, so the same phrase always reads at the same place on the meter.
private struct MeterBlock: View {
    let decibels: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LevelMeter(decibels: decibels, segments: 22, segmentHeight: 9, onDevice: true)
            ScaleMarks()
        }
        .accessibilityHidden(true)
    }
}

private struct ScaleMarks: View {
    /// Fractions of the ladder that carry a printed mark: floor, −40, −20, and the
    /// caution point where a real meter prints its last division before clipping.
    private let marks: [(position: Double, tall: Bool)] = [
        (0.0, true), (0.25, false), (0.5, false), (0.82, true), (1.0, false)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(marks.indices, id: \.self) { index in
                    Rectangle()
                        .fill(Device.engravedDim.opacity(marks[index].tall ? 0.85 : 0.5))
                        .frame(width: 1, height: marks[index].tall ? 4 : 2.5)
                        .offset(x: proxy.size.width * marks[index].position)
                }
            }
        }
        .frame(height: 4)
    }
}
