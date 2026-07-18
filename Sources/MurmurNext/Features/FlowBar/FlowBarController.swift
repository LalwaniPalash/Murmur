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
        orchestrator.$lastError
            .sink { [weak self] in
                if let error = $0 { self?.message = error }
            }
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

    private var panelSize: CGSize {
        phase == .failed ? CGSize(width: 320, height: 54) : CGSize(width: 142, height: 42)
    }
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

private struct FlowBarView: View {
    @ObservedObject var controller: FlowBarController

    var body: some View {
        HStack(spacing: 10) {
            if (controller.phase == .listening || controller.phase == .calibrating)
                && controller.showsAudioMovement {
                AudioBars(level: controller.audioLevelDecibels, whisperLikelihood: controller.whisperLikelihood)
            } else if controller.phase == .listening || controller.phase == .calibrating {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            } else if controller.phase == .finalizing || controller.phase == .inserting {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
            }

            Text(statusText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(controller.phase == .failed ? 2 : 1)

            if controller.phase == .listening || controller.phase == .calibrating {
                Button { controller.cancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel dictation")
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(Color(red: 0.09, green: 0.085, blue: 0.075).opacity(0.97))
                .shadow(color: .black.opacity(0.24), radius: 18, y: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(.white.opacity(0.09))
        }
    }

    private var statusText: String {
        switch controller.phase {
        case .calibrating: "Tuning in"
        case .listening: controller.whisperLikelihood > 0.45 ? "Hearing whisper" : "Listening"
        case .finalizing: "Correcting"
        case .inserting: "Writing"
        case .completed: "Inserted"
        case .failed: controller.message.isEmpty ? "Try that again" : controller.message
        case .cancelled: "Cancelled"
        case .idle: "Ready"
        }
    }

    private var statusIcon: String {
        controller.phase == .completed ? "checkmark" : controller.phase == .failed ? "exclamationmark" : "xmark"
    }

    private var statusColor: Color {
        controller.phase == .failed ? .orange : .white.opacity(0.84)
    }
}

private struct AudioBars: View {
    let level: Double
    let whisperLikelihood: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.88))
                    .frame(width: 2.5, height: height(index))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
        .frame(width: 16, height: 18)
        .accessibilityHidden(true)
    }

    private func height(_ index: Int) -> CGFloat {
        let normalized = min(max((level + 60) / 48, 0.08), 1)
        let shapes = [0.55, 1.0, 0.76, 0.42]
        let whisperBoost = whisperLikelihood > 0.45 ? 0.18 : 0
        return 4 + CGFloat(min(normalized + whisperBoost, 1) * shapes[index] * 13)
    }
}
