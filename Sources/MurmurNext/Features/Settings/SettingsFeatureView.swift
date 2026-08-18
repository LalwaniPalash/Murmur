import AVFoundation
import SwiftUI

/// The Settings window keeps the native macOS tab chrome — this is the most
/// convention-bound window in a Mac app, and fighting it would cost more than it buys.
/// Everything inside a tab is panel language.
///
/// Thirteen sections became six. Shortcuts moved onto the panel's own legend, and the
/// Models section was a card whose only content was a button to somewhere else.
struct SettingsFeatureView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }
            DictationSettings().tabItem { Label("Dictation", systemImage: "waveform") }
            FlowBarSettings().tabItem { Label("Flow Bar", systemImage: "rectangle.inset.filled") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "lock") }
            StorageSettings().tabItem { Label("Storage", systemImage: "externaldrive") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "flask") }
        }
    }
}

// MARK: - Scaffold

/// Every pane carries the same size so switching tabs never resizes the window, and the
/// panel finish reaches the window edges instead of sitting as an island on system white.
private struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
                content
            }
            .padding(MurmurTheme.Space.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 540, height: 420)
        .background(MurmurTheme.Finish.panel)
    }
}

@MainActor
private func settingBinding(
    _ environment: AppEnvironment,
    _ keyPath: WritableKeyPath<MurmurSettingsRecord, Bool>
) -> Binding<Bool> {
    Binding(
        get: { environment.settings[keyPath: keyPath] },
        set: { value in environment.updateSettings { $0[keyPath: keyPath] = value } }
    )
}

// MARK: - Panes

private struct GeneralSettings: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        SettingsPane {
            PanelSection(legend: "Startup") {
                Plate {
                    VStack(spacing: 0) {
                        LaunchAtLoginSettingView()
                        ScribeRule()
                        PanelSwitch(
                            legend: "Menu bar item",
                            isOn: settingBinding(environment, \.showMenuBarItem)
                        )
                    }
                }
            }

            PanelSection(legend: "Notifications") {
                Plate {
                    VStack(spacing: 0) {
                        PanelSwitch(
                            legend: "Errors",
                            detail: "Problems that need you to do something.",
                            isOn: settingBinding(environment, \.errorNotifications)
                        )
                        ScribeRule()
                        PanelSwitch(
                            legend: "Milestones",
                            isOn: settingBinding(environment, \.milestoneNotifications)
                        )
                    }
                }
            }

            PanelSection(legend: "Build") {
                Plate {
                    VStack(spacing: 0) {
                        SpecLine(legend: "Version", value: Self.version)
                        ScribeRule()
                        SpecLine(legend: "Transcription", value: "On this Mac")
                        ScribeRule()
                        SpecLine(legend: "Writing", value: writingRouteLabel)
                    }
                }
            }
        }
    }

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short ?? "dev"
    }

    private var writingRouteLabel: String {
        switch environment.settings.writing.route {
        case .deterministic: "Deterministic"
        case .openAI: "OpenAI · your key"
        case .openAICompatible: "Compatible · your key"
        case .localMLX: "Local model"
        }
    }
}

private struct DictationSettings: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        SettingsPane {
            PanelSection(legend: "Capture") {
                Plate {
                    VStack(spacing: 0) {
                        PanelSwitch(
                            legend: "Whisper-aware",
                            detail: "Adapts the threshold for quiet speech.",
                            isOn: settingBinding(environment, \.whisperAwareCapture)
                        )
                        ScribeRule()
                        SpecLine(legend: "Input", value: Self.defaultMicrophoneName)
                        ScribeRule()
                        SpecLine(legend: "Calibration", value: "Adaptive")
                        ScribeRule()
                        SpecLine(legend: "Language", value: "English")
                    }
                }
            }

            PanelSection(legend: "Correction") {
                Plate {
                    VStack(alignment: .leading, spacing: MurmurTheme.Space.medium) {
                        PanelSwitch(
                            legend: "Remove fillers and false starts",
                            isOn: settingBinding(environment, \.removeSpeechArtifacts)
                        )
                        ScribeRule()
                        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                            Legend("Strength", size: .micro, color: MurmurTheme.Engraving.tertiary)
                            Picker(
                                "",
                                selection: Binding(
                                    get: { environment.settings.cleanupIntensity },
                                    set: { value in
                                        environment.updateSettings { $0.cleanupIntensity = value }
                                    }
                                )
                            ) {
                                ForEach(CleanupIntensity.allCases) { intensity in
                                    Text(intensity.title).tag(intensity)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Cleanup strength")
                        }
                    }
                }
            }
        }
    }

    private static var defaultMicrophoneName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "System default"
    }
}

private struct FlowBarSettings: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        SettingsPane {
            PanelSection(legend: "Flow Bar") {
                Plate {
                    VStack(spacing: 0) {
                        PanelSwitch(
                            legend: "Live level meter",
                            detail: "Shows input level. Never shows unfinished words.",
                            isOn: settingBinding(environment, \.showLiveAudioMovement)
                        )
                        ScribeRule()
                        PanelSwitch(
                            legend: "Edge docking",
                            detail: "Remembers position per display.",
                            isOn: settingBinding(environment, \.allowFlowBarDocking)
                        )
                    }
                }
            }
        }
    }
}

private struct PrivacySettings: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        SettingsPane {
            PanelSection(legend: "Processing") {
                Plate {
                    VStack(spacing: 0) {
                        SpecLine(legend: "Transcription", value: "This Mac", lamp: .verify, isLit: true)
                        ScribeRule()
                        SpecLine(legend: "Writing", value: writingLocation, lamp: .verify, isLit: true)
                        ScribeRule()
                        SpecLine(legend: "Cloud fallback", value: "None")
                        ScribeRule()
                        SpecLine(legend: "Telemetry", value: "None")
                    }
                }
            }

            DiagnosticsSettingsView(environment: environment)
        }
    }

    private var writingLocation: String {
        switch environment.settings.writing.route {
        case .openAI: "OpenAI · your key"
        case .openAICompatible: "Configured provider"
        case .localMLX, .deterministic: "This Mac"
        }
    }
}

private struct StorageSettings: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var proposedDisabledPolicy = false

    var body: some View {
        SettingsPane {
            PanelSection(legend: "On this Mac") {
                Plate {
                    VStack(spacing: 0) {
                        SpecLine(legend: "History", value: "Encrypted", lamp: .verify, isLit: true)
                        ScribeRule()
                        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                            Legend("Encrypted recording retention", size: .micro, color: MurmurTheme.Engraving.tertiary)
                            Picker(
                                "Retention",
                                selection: Binding(
                                    get: { environment.settings.audioRetentionPolicy },
                                    set: { policy in
                                        if policy == .disabled,
                                           environment.settings.audioRetentionPolicy.isEnabled {
                                            proposedDisabledPolicy = true
                                        } else {
                                            environment.setAudioRetentionPolicy(policy)
                                        }
                                    }
                                )
                            ) {
                                ForEach(AudioRetentionPolicy.allCases) { policy in
                                    Text(policy.title).tag(policy)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            Text("Off by default. Seven days is suggested. Audio never leaves this Mac.")
                                .font(MurmurFace.body(11))
                                .foregroundStyle(MurmurTheme.Engraving.secondary)
                        }
                    }
                }
            }

            StorageTransferSettingsView(environment: environment)
        }
        .confirmationDialog(
            "Disable retention and permanently delete all retained recordings?",
            isPresented: $proposedDisabledPolicy,
            titleVisibility: .visible
        ) {
            Button("Disable and delete recordings", role: .destructive) {
                environment.setAudioRetentionPolicy(.disabled)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Transcript history will remain. Encrypted audio cannot be recovered after deletion.")
        }
    }
}

private struct AdvancedSettings: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        SettingsPane {
            PanelSection(legend: "In progress", note: "Local features still being refined.") {
                Plate {
                    VStack(spacing: 0) {
                        PanelSwitch(
                            legend: "Command Mode",
                            detail: "Transform selected text with a spoken instruction.",
                            isOn: settingBinding(environment, \.commandModeEnabled)
                        )
                        ScribeRule()
                        PanelSwitch(
                            legend: "Workspace tagging",
                            detail: "Resolve spoken file names inside approved folders.",
                            isOn: settingBinding(environment, \.workspaceTaggingEnabled)
                        )
                    }
                }
            }
        }
    }
}
