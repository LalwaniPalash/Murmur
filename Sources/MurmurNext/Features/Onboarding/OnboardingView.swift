import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionCenter
    @ObservedObject var modelInstaller: WhisperModelInstaller
    let modelInstalled: Bool
    let completion: () -> Void
    @State private var step = 0

    var body: some View {
        ZStack {
            MurmurTheme.ColorToken.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? MurmurTheme.ColorToken.ink : MurmurTheme.ColorToken.line)
                            .frame(width: 38, height: 3)
                    }
                }
                .padding(.top, 30)

                Spacer()
                Group {
                    switch step {
                    case 0: privacyStep
                    case 1: permissionStep
                    case 2: modelStep
                    default: shortcutStep
                    }
                }
                .frame(maxWidth: 580)
                Spacer()

                HStack {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .buttonStyle(MurmurSecondaryButtonStyle())
                    }
                    Spacer()
                    Button(step == 3 ? "Start using Murmur" : "Continue") {
                        if step == 3 { completion() } else { step += 1 }
                    }
                    .buttonStyle(MurmurPrimaryButtonStyle())
                    .disabled(step == 1 && permissions.requiredPermissionsGranted == false)
                    .disabled(step == 2 && isModelReady == false)
                }
                .padding(30)
            }
        }
        .preferredColorScheme(.light)
    }

    private var privacyStep: some View {
        OnboardingCard(
            icon: "waveform.and.mic",
            eyebrow: "Welcome to Murmur",
            title: "Your voice stays yours.",
            message: "Murmur transcribes, corrects, and stores your words on this Mac. There is no cloud inference fallback."
        )
    }

    private var permissionStep: some View {
        VStack(spacing: 24) {
            OnboardingCard(
                icon: "hand.raised",
                eyebrow: "Two permissions",
                title: "Listen here. Write anywhere.",
                message: "Microphone access lets Murmur hear you. Accessibility lets it place the final corrected text in the field you chose."
            )
            HStack(spacing: 12) {
                PermissionButton(title: "Microphone", granted: permissions.microphoneGranted) {
                    Task { await permissions.requestMicrophone() }
                }
                PermissionButton(title: "Accessibility", granted: permissions.accessibilityGranted) {
                    permissions.requestAccessibilityPrompt()
                }
            }
            Button("Refresh permission status") { permissions.refresh() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
        }
    }

    private var modelStep: some View {
        VStack(spacing: 24) {
            OnboardingCard(
            icon: isModelReady ? "checkmark.seal" : "arrow.down.circle",
            eyebrow: "Local intelligence",
            title: isModelReady ? "Your model is ready." : "One model, entirely local.",
            message: isModelReady
                ? "Murmur found a verified English transcription model on this Mac."
                : "Install the recommended English model now. Dictation remains offline after this one-time download."
            )
            if isModelReady == false {
                modelInstallControl
            }
        }
    }

    private var shortcutStep: some View {
        VStack(spacing: 26) {
            OnboardingCard(
                icon: "keyboard",
                eyebrow: "Your shortcut",
                title: "Hold fn. Speak. Release.",
                message: "Speak normally or whisper. Correct yourself naturally—Murmur inserts only the reconciled sentence after you release."
            )
            Text("fn")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(MurmurTheme.ColorToken.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(MurmurTheme.ColorToken.line) }
        }
    }

    @ViewBuilder
    private var modelInstallControl: some View {
        switch modelInstaller.state {
        case .downloading:
            VStack(spacing: 9) {
                ProgressView(value: modelInstaller.progress).frame(width: 320)
                Text("Downloading \(Int(modelInstaller.progress * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                Button("Cancel") { modelInstaller.cancel() }
                    .buttonStyle(.plain)
            }
        case .verifying:
            ProgressView("Verifying model…").controlSize(.small)
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(MurmurTheme.ColorToken.danger)
                    .multilineTextAlignment(.center)
                Button("Try again") { modelInstaller.install(.smallEnglish) }
                    .buttonStyle(MurmurPrimaryButtonStyle())
            }
        case .idle, .installed:
            Button("Install recommended model · 488 MB") {
                modelInstaller.install(.smallEnglish)
            }
            .buttonStyle(MurmurPrimaryButtonStyle())
        }
    }

    private var isModelReady: Bool {
        if modelInstalled { return true }
        if case .installed = modelInstaller.state { return true }
        return false
    }
}

private struct OnboardingCard: View {
    let icon: String
    let eyebrow: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(MurmurTheme.ColorToken.ink)
                .frame(width: 62, height: 62)
                .background(MurmurTheme.ColorToken.sidebar)
                .clipShape(Circle())
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(MurmurTheme.ColorToken.ink)
            Text(message)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                .lineSpacing(3)
        }
    }
}

private struct PermissionButton: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(granted ? MurmurTheme.ColorToken.success : MurmurTheme.ColorToken.tertiaryInk)
                Text(title)
                Spacer()
                Text(granted ? "Ready" : "Allow")
                    .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(width: 220, height: 46)
            .background(MurmurTheme.ColorToken.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(MurmurTheme.ColorToken.line) }
        }
        .buttonStyle(.plain)
        .disabled(granted)
    }
}
