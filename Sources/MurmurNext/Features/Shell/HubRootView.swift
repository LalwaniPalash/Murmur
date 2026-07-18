import SwiftUI

struct HubRootView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        Group {
            if environment.hasCompletedOnboarding {
                hub
            } else {
                OnboardingView(
                    permissions: environment.permissionCenter,
                    modelInstaller: environment.modelInstaller,
                    modelInstalled: environment.hasInstalledWhisperModel,
                    completion: environment.completeOnboarding
                )
            }
        }
        .background(MurmurTheme.ColorToken.canvas)
        .preferredColorScheme(.light)
        .overlay(alignment: .top) {
            if let message = environment.persistenceError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MurmurTheme.ColorToken.warning)
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        environment.clearPresentedError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
                .background(MurmurTheme.ColorToken.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(MurmurTheme.ColorToken.line) }
                .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
                .padding(.top, 12)
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var hub: some View {
        HStack(spacing: 0) {
            HubSidebar(selection: $environment.selectedDestination)
                .frame(width: 218)
            Rectangle()
                .fill(MurmurTheme.ColorToken.line)
                .frame(width: 1)
            destinationView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MurmurTheme.ColorToken.canvas)
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch environment.selectedDestination {
        case .home:
            HomeFeatureView(environment: environment)
        case .dictionary:
            DictionaryFeatureView(environment: environment)
        case .snippets:
            SnippetsFeatureView(environment: environment)
        case .style:
            StyleFeatureView(environment: environment)
        case .scratchpad:
            ScratchpadLandingView(environment: environment)
        case .models:
            ModelsFeatureView(environment: environment)
        case .settings:
            SettingsFeatureView()
        case .help:
            HelpFeatureView()
        }
    }
}

private struct HubSidebar: View {
    @Binding var selection: HubDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                MurmurGlyph()
                Text("Murmur")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(MurmurTheme.ColorToken.ink)
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 26)

            VStack(spacing: 3) {
                ForEach([HubDestination.home, .dictionary, .snippets, .style, .scratchpad, .models]) { destination in
                    SidebarButton(destination: destination, selection: $selection)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(spacing: 3) {
                SidebarButton(destination: .settings, selection: $selection)
                SidebarButton(destination: .help, selection: $selection)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .background(MurmurTheme.ColorToken.sidebar)
    }
}

private struct SidebarButton: View {
    let destination: HubDestination
    @Binding var selection: HubDestination

    var body: some View {
        Button {
            selection = destination
        } label: {
            HStack(spacing: 11) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(destination.title)
                    .font(.system(size: 13, weight: selection == destination ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(MurmurTheme.ColorToken.ink.opacity(selection == destination ? 1 : 0.72))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(selection == destination ? MurmurTheme.ColorToken.selected : .clear)
            .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Radius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
    }
}

private struct MurmurGlyph: View {
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach([8.0, 14.0, 19.0, 12.0, 7.0], id: \.self) { height in
                Capsule()
                    .fill(MurmurTheme.ColorToken.ink)
                    .frame(width: 2.2, height: height)
            }
        }
        .frame(width: 25, height: 25)
        .accessibilityHidden(true)
    }
}

private struct HelpFeatureView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
                PageHeader(title: "Help", subtitle: "Learn the shortcuts and resolve common setup issues.")
                MurmurCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Hold your dictation shortcut and speak naturally.", systemImage: "keyboard")
                        Label("Whispering works best within an arm's length of your microphone.", systemImage: "waveform")
                        Label("Murmur only inserts text after local correction is complete.", systemImage: "checkmark.seal")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                }
            }
            .padding(MurmurTheme.Space.xLarge)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }
}
