import AppKit
import SwiftUI

@MainActor
final class FloatingBarController: ObservableObject {
    @Published var isVisible = false
    @Published var mode: DictationMode?
    @Published var phase: SessionPhase = .idle
    @Published var transcriptText = ""
    @Published var audioLevel: Double = -80
    @Published var context: AppWritingContext = .unknown

    private var panel: FloatingBarPanel?

    func show(
        mode: DictationMode,
        phase: SessionPhase,
        transcriptText: String,
        audioLevel: Double,
        context: AppWritingContext,
        anchorFrame: CGRect?
    ) {
        self.mode = mode
        self.phase = phase
        self.transcriptText = transcriptText
        self.audioLevel = audioLevel
        self.context = context
        isVisible = true
        ensurePanel()
        positionPanel(anchorFrame: anchorFrame)
        panel?.orderFrontRegardless()
    }

    func update(
        phase: SessionPhase? = nil,
        transcriptText: String? = nil,
        audioLevel: Double? = nil,
        context: AppWritingContext? = nil,
        anchorFrame: CGRect? = nil
    ) {
        if let phase {
            self.phase = phase
        }
        if let transcriptText {
            self.transcriptText = transcriptText
        }
        if let audioLevel {
            self.audioLevel = audioLevel
        }
        if let context {
            self.context = context
        }
        if anchorFrame != nil || phase != nil || transcriptText != nil {
            positionPanel(anchorFrame: anchorFrame)
        }
    }

    func hide() {
        isVisible = false
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let size = panelSize
        panel = FloatingBarPanel(contentRect: CGRect(origin: .zero, size: size))
        panel?.contentView = NSHostingView(rootView: FloatingBarView(controller: self))
    }

    private func positionPanel(anchorFrame: CGRect?) {
        guard let panel else { return }
        guard let screen = NSScreen.main else { return }

        let visible = screen.visibleFrame
        let size = panelSize
        let width = size.width
        let height = size.height
        let targetX = visible.midX - width / 2
        let targetY = visible.minY + 20

        panel.setFrame(CGRect(x: targetX, y: targetY, width: width, height: height), display: true)
    }

    private var panelSize: CGSize {
        switch phase {
        case .listening, .processing, .idle:
            CGSize(width: 124, height: 34)
        case .completed:
            CGSize(width: hasFallbackMessage ? 218 : 112, height: 34)
        case .failed:
            CGSize(width: 280, height: 46)
        }
    }

    private var hasFallbackMessage: Bool {
        transcriptText.localizedCaseInsensitiveContains("Basic formatting applied")
            || transcriptText.localizedCaseInsensitiveContains("AI model unavailable")
    }
}

private final class FloatingBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
    }
}

private struct FloatingBarView: View {
    @ObservedObject var controller: FloatingBarController
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 9) {
            if showsActivityBars {
                ActivityBars(animationPhase: animationPhase, phase: controller.phase, audioLevel: controller.audioLevel)
            } else {
                StatusDot(phase: controller.phase)
            }
            Text(statusLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(controller.phase == .failed ? 2 : 1)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color(red: 0.045, green: 0.044, blue: 0.04).opacity(0.96))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .onAppear {
            startAnimation()
        }
    }

    private var showsActivityBars: Bool {
        switch controller.phase {
        case .listening, .processing, .idle:
            true
        case .completed, .failed:
            false
        }
    }

    private var statusLabel: String {
        switch controller.phase {
        case .listening:
            "Listening"
        case .processing:
            "Writing"
        case .completed:
            hasFallbackMessage ? "Basic formatting applied" : "Inserted"
        case .failed:
            displayText.isEmpty ? "Unable to complete" : displayText
        case .idle:
            "Ready"
        }
    }

    private var displayText: String {
        controller.transcriptText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private var hasFallbackMessage: Bool {
        controller.transcriptText.localizedCaseInsensitiveContains("Basic formatting applied")
            || controller.transcriptText.localizedCaseInsensitiveContains("AI model unavailable")
    }

    private func startAnimation() {
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            animationPhase = 1.0
        }
    }
}

private struct StatusDot: View {
    let phase: SessionPhase

    var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: 6, height: 6)
    }

    private var fillColor: Color {
        switch phase {
        case .completed:
            .white.opacity(0.82)
        case .failed:
            .red.opacity(0.9)
        case .listening, .processing, .idle:
            .white.opacity(0.65)
        }
    }
}

private struct ActivityBars: View {
    let animationPhase: CGFloat
    let phase: SessionPhase
    let audioLevel: Double

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(barOpacity))
                    .frame(width: 2.5, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.45).delay(Double(index) * 0.04), value: animationPhase)
                    .animation(.easeOut(duration: 0.18), value: audioLevel)
            }
        }
        .frame(width: 20, height: 14)
    }

    private var barOpacity: Double {
        switch phase {
        case .listening, .processing:
            0.95
        case .failed:
            0.58
        case .completed, .idle:
            0.46
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard phase == .listening || phase == .processing else { return 8 }
        let normalizedLevel = CGFloat(min(max((audioLevel + 60) / 60, 0), 1))
        let wave = sin((animationPhase * 2 * .pi) + CGFloat(index) * 0.85)
        let animated = CGFloat(0.5 + 0.5 * wave)
        return 4 + (animated * 6) + (normalizedLevel * 3)
    }
}
