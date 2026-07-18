import AVFoundation
import SwiftUI

struct SettingsFeatureView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: 190)
            .background(MurmurTheme.ColorToken.sidebar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(title: selectedSection.title, subtitle: selectedSection.subtitle)
                    settingsContent
                }
                .padding(MurmurTheme.Space.xLarge)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .background(MurmurTheme.ColorToken.canvas)
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedSection {
        case .general:
            MurmurCard {
                LaunchAtLoginSettingView()
                Divider().padding(.vertical, 8)
                SettingsToggle(
                    title: "Show Murmur in the menu bar",
                    detail: "Open the Hub and Scratchpad from anywhere.",
                    isOn: settingBinding(\.showMenuBarItem)
                )
            }
        case .dictation:
            MurmurCard {
                SettingsToggle(
                    title: "Remove fillers and false starts",
                    detail: "Keep only your intended sentence.",
                    isOn: settingBinding(\.removeSpeechArtifacts)
                )
                Divider().padding(.vertical, 8)
                SettingsToggle(
                    title: "Whisper-aware capture",
                    detail: "Adapt the microphone threshold for quiet speech.",
                    isOn: settingBinding(\.whisperAwareCapture)
                )
            }
        case .languages:
            MurmurCard {
                LabeledContent("Primary language") { Text("English") }
                Text("Additional languages will appear after they have dedicated quality evaluation.")
                    .font(.system(size: 12))
                    .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
            }
        case .microphone:
            MurmurCard {
                LabeledContent("Input") { Text(defaultMicrophoneName) }
                Divider().padding(.vertical, 8)
                LabeledContent("Quiet-speech calibration") { Text("Adaptive each session") }
            }
        case .cleanup:
            MurmurCard {
                Picker(
                    "Cleanup level",
                    selection: Binding(
                        get: { environment.settings.cleanupIntensity },
                        set: { value in environment.updateSettings { $0.cleanupIntensity = value } }
                    )
                ) {
                    ForEach(CleanupIntensity.allCases) { intensity in
                        Text(intensity.title).tag(intensity)
                    }
                }
                .pickerStyle(.segmented)
                Text("Remove speech artifacts and improve structure without changing your meaning.")
                    .font(.system(size: 12))
                    .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
            }
        case .shortcuts:
            MurmurCard {
                ShortcutRow(title: "Dictate", shortcut: "fn")
                Divider().padding(.vertical, 8)
                ShortcutRow(title: "Command Mode", shortcut: "fn  control")
                Divider().padding(.vertical, 8)
                ShortcutRow(title: "Scratchpad", shortcut: "option  S")
            }
        case .flowBar:
            MurmurCard {
                SettingsToggle(
                    title: "Show live audio movement",
                    detail: "Use a waveform without revealing provisional text.",
                    isOn: settingBinding(\.showLiveAudioMovement)
                )
                Divider().padding(.vertical, 8)
                SettingsToggle(
                    title: "Allow screen-edge docking",
                    detail: "Remember the Flow Bar position per display.",
                    isOn: settingBinding(\.allowFlowBarDocking)
                )
            }
        case .notifications:
            MurmurCard {
                SettingsToggle(
                    title: "Errors and recovery",
                    detail: "Always show problems that require action.",
                    isOn: settingBinding(\.errorNotifications)
                )
                Divider().padding(.vertical, 8)
                SettingsToggle(
                    title: "Milestones",
                    detail: "Celebrate writing streaks locally.",
                    isOn: settingBinding(\.milestoneNotifications)
                )
            }
        case .privacy:
            VStack(spacing: 12) {
                MurmurCard {
                    Label("Transcription and cleanup stay on this Mac.", systemImage: "lock.shield")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Murmur has no cloud inference fallback. Temporary audio is discarded after processing by default.")
                        .font(.system(size: 12))
                        .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                }
                DiagnosticsSettingsView(environment: environment)
            }
        case .storage:
            VStack(spacing: 12) {
                MurmurCard {
                    LabeledContent("History") { Text("Encrypted locally") }
                    Divider().padding(.vertical, 8)
                    SettingsToggle(
                        title: "Retain raw audio",
                        detail: "Off by default. Audio never leaves this Mac.",
                        isOn: settingBinding(\.retainRawAudio)
                    )
                }
                StorageTransferSettingsView(environment: environment)
            }
        case .models:
            MurmurCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Transcription models now have their own workspace.", systemImage: "cpu")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Compare speed and quality, download verified models, switch the active model, or reclaim storage from the Models page.")
                        .font(.system(size: 12))
                        .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                    Button("Open Models") { environment.selectedDestination = .models }
                        .buttonStyle(MurmurPrimaryButtonStyle())
                }
            }
        case .experimental:
            MurmurCard {
                SettingsToggle(
                    title: "Command Mode",
                    detail: "Transform selected text with a spoken instruction.",
                    isOn: settingBinding(\.commandModeEnabled)
                )
                Divider().padding(.vertical, 8)
                SettingsToggle(
                    title: "Local workspace tagging",
                    detail: "Resolve spoken file names inside approved folders.",
                    isOn: settingBinding(\.workspaceTaggingEnabled)
                )
            }
        case .about:
            MurmurCard {
                Text("Murmur")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Private voice writing for macOS")
                    .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
            }
        }
    }

    private func settingBinding(_ keyPath: WritableKeyPath<MurmurSettingsRecord, Bool>) -> Binding<Bool> {
        Binding(
            get: { environment.settings[keyPath: keyPath] },
            set: { value in environment.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private var defaultMicrophoneName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "System default"
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, dictation, languages, microphone, cleanup, shortcuts, flowBar, notifications, privacy, storage, models, experimental, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .dictation: "Dictation"
        case .languages: "Languages"
        case .microphone: "Microphone"
        case .cleanup: "Cleanup"
        case .shortcuts: "Shortcuts"
        case .flowBar: "Flow Bar"
        case .notifications: "Notifications"
        case .privacy: "Privacy"
        case .storage: "Storage"
        case .models: "Models"
        case .experimental: "Experimental"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Choose how Murmur behaves on your Mac."
        case .dictation: "Control what happens between speaking and insertion."
        case .languages: "Set the language Murmur expects to hear."
        case .microphone: "Select and calibrate your input device."
        case .cleanup: "Decide how strongly Murmur refines your words."
        case .shortcuts: "Reach every voice mode without leaving your work."
        case .flowBar: "Tune the floating feedback shown while you speak."
        case .notifications: "Choose which local updates deserve attention."
        case .privacy: "Review how your voice and writing stay private."
        case .storage: "Manage local history, audio, and backups."
        case .models: "Install and verify local transcription and cleanup models."
        case .experimental: "Try local features that are still being refined."
        case .about: "Version, acknowledgements, and support information."
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .dictation: "waveform"
        case .languages: "globe"
        case .microphone: "mic"
        case .cleanup: "wand.and.stars"
        case .shortcuts: "keyboard"
        case .flowBar: "capsule"
        case .notifications: "bell"
        case .privacy: "lock"
        case .storage: "externaldrive"
        case .models: "cpu"
        case .experimental: "flask"
        case .about: "info.circle"
        }
    }
}

private struct SettingsToggle: View {
    let title: String
    let detail: String
    @State private var isOn: Bool
    private let externalBinding: Binding<Bool>?

    init(title: String, detail: String, initialValue: Bool = false) {
        self.title = title
        self.detail = detail
        _isOn = State(initialValue: initialValue)
        externalBinding = nil
    }

    init(title: String, detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = State(initialValue: isOn.wrappedValue)
        externalBinding = isOn
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
            }
            Spacer()
            Toggle("", isOn: externalBinding ?? $isOn).labelsHidden()
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(MurmurTheme.ColorToken.sidebar)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
