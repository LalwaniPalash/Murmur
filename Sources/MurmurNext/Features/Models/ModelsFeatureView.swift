import SwiftUI

struct ModelsFeatureView: View {
    @ObservedObject private var environment: AppEnvironment
    @ObservedObject private var installer: WhisperModelInstaller
    @State private var pendingRemoval: WhisperDownloadManifest?
    @State private var removalError: String?

    init(environment: AppEnvironment) {
        self.environment = environment
        _installer = ObservedObject(wrappedValue: environment.modelInstaller)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
                PageHeader(
                    title: "Models",
                    subtitle: "Choose the local Whisper model that best fits your speed, quality, and language needs."
                )
                summaryCard
                recommendationCard

                ForEach(WhisperModelLanguage.allCases) { language in
                    modelSection(language)
                }

                if case .failed(let message) = installer.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MurmurTheme.ColorToken.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(MurmurTheme.ColorToken.surfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Radius.small))
                }

                if let removalError {
                    Label(removalError, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MurmurTheme.ColorToken.danger)
                }
            }
            .padding(MurmurTheme.Space.xLarge)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .alert(removalAlertTitle, isPresented: removalAlertBinding) {
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
            Button("Delete", role: .destructive) { deletePendingModel() }
        } message: {
            Text(removalAlertMessage)
        }
    }

    private var summaryCard: some View {
        MurmurCard {
            HStack(spacing: 0) {
                SummaryMetric(
                    title: "Active model",
                    value: activeManifest?.displayName ?? "None available"
                )
                Divider().frame(height: 42).padding(.horizontal, 22)
                SummaryMetric(
                    title: "Installed",
                    value: "\(installedIdentifiers.count)"
                )
                Divider().frame(height: 42).padding(.horizontal, 22)
                SummaryMetric(
                    title: "Local storage",
                    value: Self.formattedSize(installedByteCount)
                )
                Spacer(minLength: 0)
            }
        }
    }

    private var recommendationCard: some View {
        MurmurCard {
            HStack(spacing: 14) {
                Image(systemName: "speedometer")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(MurmurTheme.ColorToken.ink)
                    .frame(width: 38, height: 38)
                    .background(MurmurTheme.ColorToken.selected)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Small English is recommended")
                        .font(.system(size: 14, weight: .semibold))
                    Text("It is much lighter than Large v3 Turbo while preserving strong English and whisper performance.")
                        .font(.system(size: 12))
                        .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                }
                Spacer()
                ModelBadge(text: Self.formattedSize(WhisperDownloadManifest.smallEnglish.byteCount))
            }
        }
    }

    private func modelSection(_ language: WhisperModelLanguage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MurmurTheme.ColorToken.ink)
            ForEach(WhisperDownloadManifest.supported.filter { $0.language == language }) { manifest in
                modelCard(manifest)
            }
        }
    }

    private func modelCard(_ manifest: WhisperDownloadManifest) -> some View {
        MurmurCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text(manifest.displayName)
                                .font(.system(size: 14, weight: .semibold))
                            if manifest.isRecommended {
                                ModelBadge(text: "Recommended", emphasized: true)
                            }
                            if installedIdentifiers.contains(manifest.id) {
                                ModelBadge(text: "Installed")
                            }
                        }
                        Text(manifest.qualityDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            ModelBadge(text: manifest.language.title)
                            ModelBadge(text: manifest.speed.rawValue)
                            ModelBadge(text: "\(manifest.quality) quality")
                            ModelBadge(text: Self.formattedSize(manifest.byteCount))
                        }
                    }
                    Spacer(minLength: 12)
                    modelAction(manifest)
                }

                if case .downloading(let active) = installer.state, active.id == manifest.id {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: installer.progress)
                        Text("Downloading \(Int(installer.progress * 100))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                    }
                } else if case .verifying(let active) = installer.state, active.id == manifest.id {
                    ProgressView("Verifying download…")
                        .controlSize(.small)
                        .font(.system(size: 11, weight: .medium))
                }
            }
        }
    }

    @ViewBuilder
    private func modelAction(_ manifest: WhisperDownloadManifest) -> some View {
        if installedIdentifiers.contains(manifest.id) {
            HStack(spacing: 10) {
                if environment.settings.preferredWhisperModelIdentifier == manifest.id {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MurmurTheme.ColorToken.success)
                } else {
                    Button("Use") { environment.activateWhisperModel(identifier: manifest.id) }
                        .buttonStyle(MurmurSecondaryButtonStyle())
                }
                Button {
                    removalError = nil
                    pendingRemoval = manifest
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                .accessibilityLabel("Delete \(manifest.displayName)")
                .help("Delete this model from this Mac")
            }
        } else if case .downloading(let active) = installer.state, active.id == manifest.id {
            Button("Cancel") { installer.cancel() }
                .buttonStyle(MurmurSecondaryButtonStyle())
        } else if case .verifying(let active) = installer.state, active.id == manifest.id {
            ProgressView().controlSize(.small)
        } else {
            Button("Download & Use") { installer.install(manifest) }
                .buttonStyle(MurmurPrimaryButtonStyle())
                .disabled(isInstallerBusy)
        }
    }

    private var installedIdentifiers: Set<String> {
        var identifiers = environment.verifiedWhisperModelIdentifiers
        if case .installed(let manifest) = installer.state {
            identifiers.insert(manifest.id)
        }
        return identifiers
    }

    private var activeManifest: WhisperDownloadManifest? {
        guard installedIdentifiers.contains(environment.settings.preferredWhisperModelIdentifier) else {
            return nil
        }
        return WhisperDownloadManifest.supported.first {
            $0.id == environment.settings.preferredWhisperModelIdentifier
        }
    }

    private var installedByteCount: Int64 {
        WhisperDownloadManifest.supported
            .filter { installedIdentifiers.contains($0.id) }
            .reduce(0) { $0 + $1.byteCount }
    }

    private var isInstallerBusy: Bool {
        switch installer.state {
        case .downloading, .verifying:
            true
        case .idle, .installed, .failed:
            false
        }
    }

    private var removalAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if $0 == false { pendingRemoval = nil } }
        )
    }

    private var removalAlertTitle: String {
        guard let pendingRemoval else { return "Delete model?" }
        if installedIdentifiers.count == 1 { return "Delete your only model?" }
        if environment.settings.preferredWhisperModelIdentifier == pendingRemoval.id {
            return "Delete the active model?"
        }
        return "Delete \(pendingRemoval.displayName)?"
    }

    private var removalAlertMessage: String {
        guard let pendingRemoval else { return "" }
        if installedIdentifiers.count == 1 {
            return "Dictation will be unavailable until another model is downloaded."
        }
        if environment.settings.preferredWhisperModelIdentifier == pendingRemoval.id {
            return "Murmur will switch to the best installed fallback. You can download this model again later."
        }
        return "This removes \(Self.formattedSize(pendingRemoval.byteCount)) from this Mac. You can download it again later."
    }

    private func deletePendingModel() {
        guard let manifest = pendingRemoval else { return }
        pendingRemoval = nil
        Task { @MainActor in
            do {
                try await environment.removeWhisperModel(manifest)
            } catch {
                removalError = error.localizedDescription
            }
        }
    }

    private static func formattedSize(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MurmurTheme.ColorToken.ink)
                .lineLimit(1)
        }
    }
}

private struct ModelBadge: View {
    let text: String
    var emphasized = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: emphasized ? .semibold : .medium))
            .foregroundStyle(
                emphasized ? MurmurTheme.ColorToken.ink : MurmurTheme.ColorToken.secondaryInk
            )
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(emphasized ? MurmurTheme.ColorToken.selected : MurmurTheme.ColorToken.sidebar)
            .clipShape(Capsule())
    }
}
