import SwiftUI

/// Commissioning. Rather than four full-screen cards the user walks through blind, the
/// whole checklist stays on the panel with a lamp against each line; the current step is
/// the only one that opens. Progress is legible without a progress indicator.
struct OnboardingView: View {
    @ObservedObject var permissions: PermissionCenter
    @ObservedObject var modelInstaller: WhisperModelInstaller
    let modelInstalled: Bool
    let completion: () -> Void
    @State private var step: Step = .local

    enum Step: Int, CaseIterable, Identifiable {
        case local, permissions, model, shortcut

        var id: Int { rawValue }

        var legend: String {
            switch self {
            case .local: "Local"
            case .permissions: "Access"
            case .model: "Model"
            case .shortcut: "Key"
            }
        }

        var detail: String {
            switch self {
            case .local: "Everything runs on this Mac. No account, no cloud, no telemetry."
            case .permissions: "Microphone to hear you. Accessibility to write where your cursor is."
            case .model: "One download, then Murmur works offline."
            case .shortcut: "Hold fn, speak, release. Whisper if you need to."
            }
        }
    }

    var body: some View {
        ZStack {
            // Chassis, not panel: before the app is commissioned the user is looking at
            // the bare device, and the checklist plate is the only thing mounted on it.
            MurmurTheme.Finish.chassis.ignoresSafeArea()

            VStack(alignment: .leading, spacing: MurmurTheme.Space.xLarge) {
                HStack(spacing: MurmurTheme.Space.medium) {
                    MurmurMark(scale: 1.6)
                    Legend("Murmur", size: .title)
                    Spacer()
                    Legend("Commissioning", size: .micro, color: MurmurTheme.Engraving.tertiary)
                }
                .overlay(alignment: .bottom) { ScribeRule(strong: true, ticks: true).offset(y: 12) }

                Plate(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(Step.allCases.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { ScribeRule() }
                            CommissionRow(
                                step: item,
                                isCurrent: item == step,
                                isDone: isComplete(item),
                                content: { controls(for: item) }
                            )
                        }
                    }
                }

                HStack(spacing: MurmurTheme.Space.small) {
                    if step != .local {
                        Button("Back") { advance(-1) }
                            .buttonStyle(PanelButtonStyle(rank: .secondary))
                    }
                    Spacer()
                    Button(step == .shortcut ? "Finish" : "Continue") {
                        if step == .shortcut { completion() } else { advance(1) }
                    }
                    .buttonStyle(PanelButtonStyle(rank: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isComplete(step) == false)
                }
            }
            .frame(maxWidth: 720)
            .padding(MurmurTheme.Space.xxLarge)
        }
    }

    private func advance(_ delta: Int) {
        let next = step.rawValue + delta
        guard let target = Step(rawValue: next) else { return }
        step = target
    }

    private func isComplete(_ item: Step) -> Bool {
        switch item {
        case .local, .shortcut: true
        case .permissions: permissions.requiredPermissionsGranted
        case .model: isModelReady
        }
    }

    @ViewBuilder
    private func controls(for item: Step) -> some View {
        switch item {
        case .local:
            EmptyView()
        case .permissions:
            VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                PermissionLine(
                    legend: "Microphone",
                    granted: permissions.microphoneGranted
                ) {
                    Task { await permissions.requestMicrophone() }
                }
                PermissionLine(
                    legend: "Accessibility",
                    granted: permissions.accessibilityGranted
                ) {
                    permissions.requestAccessibilityPrompt()
                }
                Button("Recheck") { permissions.refresh() }
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
                    .padding(.top, MurmurTheme.Space.xSmall)
            }
        case .model:
            modelControl
        case .shortcut:
            HStack(spacing: MurmurTheme.Space.small) {
                KeyCap(label: "fn")
                Legend("hold", size: .micro, color: MurmurTheme.Engraving.tertiary)
            }
        }
    }

    @ViewBuilder
    private var modelControl: some View {
        switch modelInstaller.state {
        case .downloading:
            VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                HStack(spacing: MurmurTheme.Space.medium) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(MurmurTheme.Finish.recess)
                            Rectangle()
                                .fill(MurmurTheme.Engraving.ink)
                                .frame(width: proxy.size.width * min(max(modelInstaller.progress, 0), 1))
                        }
                    }
                    .frame(height: 4)
                    Text("\(Int(modelInstaller.progress * 100))%")
                        .font(MurmurFace.readout(10))
                        .monospacedDigit()
                        .foregroundStyle(MurmurTheme.Engraving.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                HStack {
                    Button("Pause") { modelInstaller.pause() }.buttonStyle(PanelButtonStyle(rank: .secondary))
                    Button("Cancel") { modelInstaller.cancel() }.buttonStyle(PanelButtonStyle(rank: .secondary))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Downloading, \(Int(modelInstaller.progress * 100)) percent")
        case .verifying:
            HStack(spacing: MurmurTheme.Space.small) {
                Lamp(colour: .caution, isLit: true)
                Legend("Verifying checksum", size: .micro, color: MurmurTheme.Engraving.secondary)
            }
        case .paused:
            HStack(spacing: MurmurTheme.Space.small) {
                Button("Resume") { modelInstaller.resume() }.buttonStyle(PanelButtonStyle(rank: .primary))
                Button("Cancel") { modelInstaller.cancel() }.buttonStyle(PanelButtonStyle(rank: .secondary))
                Legend("Download paused", size: .micro, color: MurmurTheme.Engraving.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                HStack(alignment: .top, spacing: MurmurTheme.Space.small) {
                    Lamp(colour: .caution, isLit: true)
                        .padding(.top, 3)
                    Text(message)
                        .font(MurmurFace.body(12))
                        .foregroundStyle(MurmurTheme.Engraving.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Retry") { modelInstaller.install(.smallEnglish) }
                    .buttonStyle(PanelButtonStyle(rank: .primary))
            }
        case .idle, .installed:
            if isModelReady {
                HStack(spacing: MurmurTheme.Space.small) {
                    Lamp(colour: .verify, isLit: true)
                    Legend("Verified and ready", size: .micro, color: MurmurTheme.Engraving.secondary)
                }
            } else {
                HStack(spacing: MurmurTheme.Space.medium) {
                    Button("Install") { modelInstaller.install(.smallEnglish) }
                        .buttonStyle(PanelButtonStyle(rank: .primary))
                    Legend("Small English · 488 MB", size: .micro, color: MurmurTheme.Engraving.tertiary)
                }
            }
        }
    }

    private var isModelReady: Bool {
        if modelInstalled { return true }
        if case .installed = modelInstaller.state { return true }
        return false
    }
}

// MARK: - Parts

private struct CommissionRow<Content: View>: View {
    let step: OnboardingView.Step
    let isCurrent: Bool
    let isDone: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.medium) {
            HStack(spacing: MurmurTheme.Space.medium) {
                Lamp(colour: .verify, isLit: isDone)
                Legend(
                    step.legend,
                    size: .control,
                    color: isCurrent ? MurmurTheme.Engraving.ink : MurmurTheme.Engraving.tertiary
                )
                Spacer(minLength: 0)
            }

            if isCurrent {
                Text(step.detail)
                    .font(MurmurFace.body(12.5))
                    .foregroundStyle(MurmurTheme.Engraving.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
        }
        .padding(.horizontal, MurmurTheme.Space.large)
        .padding(.vertical, MurmurTheme.Space.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? MurmurTheme.Finish.seat.opacity(0.4) : .clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(step.legend), \(isDone ? "done" : "not done")")
    }
}

private struct PermissionLine: View {
    let legend: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: MurmurTheme.Space.medium) {
            Lamp(colour: .verify, isLit: granted)
            Legend(legend, size: .control, color: MurmurTheme.Engraving.secondary)
            Spacer(minLength: MurmurTheme.Space.medium)
            if granted {
                Legend("Granted", size: .micro, color: MurmurTheme.Lamp.verify)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
            }
        }
    }
}

/// An engraved key cap. The one place the shortcut is shown at size, because it is the
/// only thing the user has to remember.
private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(MurmurFace.readout(13, weight: .medium))
            .foregroundStyle(MurmurTheme.Engraving.ink)
            .padding(.horizontal, MurmurTheme.Space.large)
            .padding(.vertical, MurmurTheme.Space.small)
            .background(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                    .fill(MurmurTheme.Finish.plate)
                    .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                    .strokeBorder(MurmurTheme.Engraving.scribeStrong, lineWidth: MurmurTheme.Space.hairline)
            )
    }
}
