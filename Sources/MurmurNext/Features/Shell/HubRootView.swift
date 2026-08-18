import SwiftUI

struct HubRootView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        Group {
            if FlowBarStateGallery.isEnabled {
                FlowBarStateGallery()
            } else if environment.hasCompletedOnboarding {
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
        .background(MurmurTheme.Finish.panel)
        .overlay(alignment: .top) {
            if let message = environment.persistenceError {
                FaultStrip(message: message, dismiss: environment.clearPresentedError)
            }
        }
    }

    private var hub: some View {
        HStack(spacing: 0) {
            LegendColumn(selection: $environment.selectedDestination)
                .frame(width: 194)
            Rectangle()
                .fill(MurmurTheme.Engraving.scribeStrong)
                .frame(width: MurmurTheme.Space.hairline)
            destinationView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(MurmurTheme.Finish.panel)
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch environment.selectedDestination {
        case .record:
            RecordFeatureView(environment: environment)
        case .vocabulary:
            VocabularyFeatureView(environment: environment)
        case .engine:
            EngineFeatureView(environment: environment)
        case .scratchpad:
            ScratchpadLandingView(environment: environment)
        }
    }
}

// MARK: - Legend column

/// The chassis the panel is bolted to. Destinations are engraved legends that seat when
/// selected, not pills that fill with colour.
private struct LegendColumn: View {
    @Binding var selection: HubDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: MurmurTheme.Space.small) {
                MurmurMark()
                Legend("Murmur", size: .section)
            }
            .padding(.horizontal, MurmurTheme.Space.large)
            .padding(.top, MurmurTheme.Space.xLarge)
            .padding(.bottom, MurmurTheme.Space.large)

            ScribeRule()
                .padding(.horizontal, MurmurTheme.Space.large)

            VStack(spacing: 1) {
                ForEach(HubDestination.allCases) { destination in
                    LegendButton(destination: destination, selection: $selection)
                }
            }
            .padding(.horizontal, MurmurTheme.Space.small)
            .padding(.top, MurmurTheme.Space.medium)

            Spacer(minLength: MurmurTheme.Space.large)

            ShortcutLegend()
                .padding(.horizontal, MurmurTheme.Space.large)
                .padding(.bottom, MurmurTheme.Space.large)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MurmurTheme.Finish.chassis)
    }
}

private struct LegendButton: View {
    let destination: HubDestination
    @Binding var selection: HubDestination
    @State private var isHovering = false

    private var isSelected: Bool { selection == destination }

    var body: some View {
        Button { selection = destination } label: {
            HStack(spacing: MurmurTheme.Space.medium) {
                Rectangle()
                    .fill(isSelected ? MurmurTheme.Engraving.ink : .clear)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Image(systemName: destination.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Legend(
                    destination.title,
                    size: .control,
                    color: isSelected ? MurmurTheme.Engraving.ink : MurmurTheme.Engraving.secondary
                )
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? MurmurTheme.Engraving.ink : MurmurTheme.Engraving.secondary)
            .padding(.trailing, MurmurTheme.Space.medium)
            .frame(height: 32)
            .background(seat)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var seat: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                .fill(MurmurTheme.Finish.seat)
        } else if isHovering {
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                .fill(MurmurTheme.Finish.seat.opacity(0.45))
        }
    }
}

/// A real device prints its key legend on the faceplate. This replaces the Help page.
private struct ShortcutLegend: View {
    private let entries: [(String, String)] = [
        ("Dictate", "fn"),
        ("Command", "⌃ fn"),
        ("Cancel", "esc"),
        ("Scratchpad", "⌥S")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
            ScribeRule()
            ForEach(entries, id: \.0) { entry in
                HStack(spacing: MurmurTheme.Space.small) {
                    Legend(entry.0, size: .micro, color: MurmurTheme.Engraving.tertiary)
                    Spacer(minLength: MurmurTheme.Space.small)
                    Text(entry.1)
                        .font(MurmurFace.readout(10, weight: .medium))
                        .foregroundStyle(MurmurTheme.Engraving.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts")
    }
}

// MARK: - Fault strip

private struct FaultStrip: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: MurmurTheme.Space.medium) {
            Lamp(colour: .caution, isLit: true)
            Text(message)
                .font(MurmurFace.body(12))
                .foregroundStyle(MurmurTheme.Engraving.ink)
                .lineLimit(2)
            Spacer(minLength: MurmurTheme.Space.medium)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(MurmurTheme.Engraving.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, MurmurTheme.Space.large)
        .frame(minHeight: 38)
        .background(
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.plate, style: .continuous)
                .fill(MurmurTheme.Finish.plate)
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.plate, style: .continuous)
                .strokeBorder(MurmurTheme.Engraving.scribeStrong, lineWidth: MurmurTheme.Space.hairline)
        )
        .padding(.top, MurmurTheme.Space.medium)
        .padding(.horizontal, MurmurTheme.Space.large)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
