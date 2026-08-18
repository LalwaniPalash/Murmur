import SwiftUI

/// The engine bay: which model is fitted, what it costs, and what else will go in.
/// Models are specification rows with tabular figures, not feature cards.
struct EngineFeatureView: View {
    @ObservedObject private var environment: AppEnvironment
    @ObservedObject private var installer: WhisperModelInstaller
    @ObservedObject private var writingTransfer: LocalWritingModelTransfer
    @State private var pendingRemoval: WhisperDownloadManifest?
    @State private var removalError: String?
    @State private var providerKey = ""
    @State private var pendingWritingModelRemoval: LocalWritingModelManifest?

    init(environment: AppEnvironment) {
        self.environment = environment
        _installer = ObservedObject(wrappedValue: environment.modelInstaller)
        _writingTransfer = ObservedObject(wrappedValue: environment.localWritingModelTransfer)
    }

    var body: some View {
        PanelPage(title: "Engine") {
            writingRouteSection
            writingBehaviorSection

            PanelSection(legend: "Fitted") {
                Plate {
                    VStack(spacing: 0) {
                        SpecLine(
                            legend: "Model",
                            value: activeManifest?.displayName ?? "None",
                            lamp: .verify,
                            isLit: activeManifest != nil
                        )
                        ScribeRule()
                        SpecLine(legend: "Installed", value: "\(installedIdentifiers.count)")
                        ScribeRule()
                        SpecLine(legend: "On disk", value: Self.formattedSize(installedByteCount))
                    }
                }
            }

            ForEach(WhisperModelLanguage.allCases) { language in
                PanelSection(legend: language.title) {
                    Plate(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(manifests(for: language).enumerated()), id: \.element.id) { index, manifest in
                                if index > 0 { ScribeRule() }
                                modelRow(manifest)
                            }
                        }
                    }
                }
            }

            if let fault {
                FaultPlate(message: fault)
            }
        }
        .alert(removalAlertTitle, isPresented: removalAlertBinding) {
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
            Button("Delete", role: .destructive) { deletePendingModel() }
        } message: {
            Text(removalAlertMessage)
        }
        .confirmationDialog(
            "Remove the local writing model?",
            isPresented: Binding(
                get: { pendingWritingModelRemoval != nil },
                set: { if $0 == false { pendingWritingModelRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove writing model", role: .destructive) {
                let manifest = pendingWritingModelRemoval
                pendingWritingModelRemoval = nil
                Task { await environment.removeLocalWritingModel(manifest) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The verified local model files will be removed. Other installed models remain available.")
        }
    }

    // MARK: Writing

    private var writingRouteSection: some View {
        PanelSection(legend: "Writing", note: "Transcription always stays local. Writing can use your key, a local model, or deterministic rules.") {
            Plate {
                VStack(alignment: .leading, spacing: MurmurTheme.Space.medium) {
                    HStack {
                        Legend("Route", size: .micro, color: MurmurTheme.Engraving.tertiary)
                        Spacer()
                        Picker("Writing route", selection: writingRouteBinding) {
                            Text("BYOK · OpenAI — Recommended").tag(WritingTransformationRoute.openAI)
                            Text("BYOK · Responses-compatible").tag(WritingTransformationRoute.openAICompatible)
                            Text("Local model").tag(WritingTransformationRoute.localMLX)
                            Text("Deterministic only").tag(WritingTransformationRoute.deterministic)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    ScribeRule()
                    writingRouteSetup
                    if let message = environment.writingSetupMessage {
                        Text(message)
                            .font(MurmurFace.body(11))
                            .foregroundStyle(MurmurTheme.Engraving.secondary)
                            .textSelection(.disabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var writingRouteSetup: some View {
        switch environment.settings.writing.route {
        case .openAI:
            providerSetup(
                providerIdentifier: "openai",
                model: Binding(
                    get: { environment.settings.writing.openAIModelIdentifier },
                    set: { value in environment.updateSettings { $0.writing.openAIModelIdentifier = value } }
                ),
                endpoint: nil
            )
        case .openAICompatible:
            providerSetup(
                providerIdentifier: "openai-compatible",
                model: Binding(
                    get: { environment.settings.writing.openAICompatibleModelIdentifier },
                    set: { value in environment.updateSettings { $0.writing.openAICompatibleModelIdentifier = value } }
                ),
                endpoint: Binding(
                    get: { environment.settings.writing.openAICompatibleEndpoint ?? "" },
                    set: { value in environment.updateSettings { $0.writing.openAICompatibleEndpoint = value } }
                )
            )
        case .localMLX:
            localWritingSetup
        case .deterministic:
            Text("Fastest and fully offline. Professional paragraph rewriting and open-ended semantic commands are disabled.")
                .font(MurmurFace.body(11.5))
                .foregroundStyle(MurmurTheme.Engraving.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func providerSetup(
        providerIdentifier: String,
        model: Binding<String>,
        endpoint: Binding<String>?
    ) -> some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
            if let endpoint {
                TextField("Responses API base URL", text: endpoint)
                    .textFieldStyle(.roundedBorder)
                Text("The endpoint must implement the OpenAI Responses API with strict JSON-schema output.")
                    .font(MurmurFace.body(10.5))
                    .foregroundStyle(MurmurTheme.Engraving.tertiary)
            }
            TextField("Model", text: model)
                .textFieldStyle(.roundedBorder)
            SecureField(
                environment.hasProviderCredential(providerIdentifier) ? "Replace saved key" : "API key",
                text: $providerKey
            )
            .textFieldStyle(.roundedBorder)
            HStack(spacing: MurmurTheme.Space.small) {
                Button(environment.hasProviderCredential(providerIdentifier) ? "Replace key" : "Save key") {
                    let key = providerKey
                    providerKey = ""
                    Task { await environment.saveProviderCredential(key, providerIdentifier: providerIdentifier) }
                }
                .buttonStyle(PanelButtonStyle(rank: .primary))
                .disabled(providerKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || environment.isWritingSetupBusy)

                Button("Test connection") {
                    Task { await environment.testSelectedWritingProvider() }
                }
                .buttonStyle(PanelButtonStyle(rank: .secondary))
                .disabled(environment.hasProviderCredential(providerIdentifier) == false || environment.isWritingSetupBusy)

                if environment.hasProviderCredential(providerIdentifier) {
                    Button("Delete key", role: .destructive) {
                        Task { await environment.deleteProviderCredential(providerIdentifier: providerIdentifier) }
                    }
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
                    .disabled(environment.isWritingSetupBusy)
                }
            }
            Text("Keys stay in macOS Keychain and are never shown again. Test connection sends only a fixed Murmur setup sentence.")
                .font(MurmurFace.body(10.5))
                .foregroundStyle(MurmurTheme.Engraving.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var localWritingSetup: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.medium) {
            HStack {
                Legend("Selection", size: .micro, color: MurmurTheme.Engraving.tertiary)
                Spacer()
                Picker("Model selection", selection: localSelectionModeBinding) {
                    Text("Automatic").tag(LocalWritingModelSelectionMode.automatic)
                    Text("Preferred").tag(LocalWritingModelSelectionMode.preferred)
                    Text("Fixed").tag(LocalWritingModelSelectionMode.fixed)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if environment.settings.writing.localModelSelectionMode != .automatic {
                Picker("Chosen model", selection: localModelIdentifierBinding) {
                    ForEach(LocalWritingModelManifest.supported) { manifest in
                        Text(manifest.displayName).tag(manifest.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            Text("Automatic uses Balanced for email and Highest quality for commands, falling back only to another verified installed model.")
                .font(MurmurFace.body(10.5))
                .foregroundStyle(MurmurTheme.Engraving.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(LocalWritingModelManifest.supported) { manifest in
                ScribeRule()
                localWritingModelRow(manifest)
            }
        }
    }

    @ViewBuilder
    private func localWritingModelRow(_ manifest: LocalWritingModelManifest) -> some View {
        let installed = environment.installedLocalWritingModelIdentifiers.contains(manifest.id)
            || (writingTransfer.manifest.id == manifest.id && writingTransfer.state == .installed)
        let activeTransfer = writingTransfer.manifest.id == manifest.id
        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
            SpecLine(legend: manifest.displayName, value: installed ? "Installed" : Self.formattedSize(manifest.byteCount), lamp: .verify, isLit: installed)
            Text("\(tierLabel(manifest.tier)) · \(manifest.license) · about \(manifest.estimatedMemoryMB) MB memory")
                .font(MurmurFace.body(10.5))
                .foregroundStyle(MurmurTheme.Engraving.tertiary)
            if activeTransfer && (writingTransfer.state == .downloading || writingTransfer.state == .paused) {
                VStack(alignment: .leading, spacing: 5) {
                    TransferBar(progress: writingTransfer.progress)
                    HStack {
                        Legend("\(writingTransfer.state == .paused ? "Paused" : "Downloading") · \(Self.formattedSize(writingTransfer.downloadedBytes)) of \(Self.formattedSize(writingTransfer.expectedBytes))", size: .micro, color: MurmurTheme.Engraving.secondary)
                        Spacer()
                        if writingTransfer.state == .downloading, writingTransfer.bytesPerSecond > 0 {
                            let remaining = Double(max(writingTransfer.expectedBytes - writingTransfer.downloadedBytes, 0))
                            Legend("\(Self.formattedSize(Int64(writingTransfer.bytesPerSecond)))/s · \(Self.formattedDuration(remaining / writingTransfer.bytesPerSecond)) left", size: .micro, color: MurmurTheme.Engraving.tertiary)
                        }
                    }
                }
                HStack(spacing: MurmurTheme.Space.small) {
                    if writingTransfer.state == .paused {
                        Button("Resume") { writingTransfer.resume() }.buttonStyle(PanelButtonStyle(rank: .secondary))
                    } else {
                        Button("Pause") { writingTransfer.pause() }.buttonStyle(PanelButtonStyle(rank: .secondary))
                    }
                    Button("Cancel") { writingTransfer.cancel() }.buttonStyle(PanelButtonStyle(rank: .secondary))
                }
            } else if activeTransfer && writingTransfer.state == .verifying {
                HStack(spacing: MurmurTheme.Space.small) {
                    ProgressView().controlSize(.small)
                    Legend("Verifying checksums", size: .micro, color: MurmurTheme.Engraving.secondary)
                }
            } else if installed {
                Button("Remove") { pendingWritingModelRemoval = manifest }
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
                    .disabled(environment.isWritingSetupBusy)
            } else {
                Button("Install \(Self.formattedSize(manifest.byteCount))") { writingTransfer.install(manifest) }
                    .buttonStyle(PanelButtonStyle(rank: .primary))
                    .disabled(environment.isWritingSetupBusy)
            }
            if activeTransfer, case .failed(let message) = writingTransfer.state { FaultPlate(message: message) }
        }
    }

    private var localSelectionModeBinding: Binding<LocalWritingModelSelectionMode> {
        Binding(
            get: { environment.settings.writing.localModelSelectionMode },
            set: { value in environment.updateSettings { $0.writing.localModelSelectionMode = value } }
        )
    }

    private var localModelIdentifierBinding: Binding<String> {
        Binding(
            get: { environment.settings.writing.localModelIdentifier },
            set: { value in environment.updateSettings { $0.writing.localModelIdentifier = value } }
        )
    }

    private func tierLabel(_ tier: LocalWritingModelTier) -> String {
        switch tier {
        case .fastest: "Fastest"
        case .balanced: "Balanced"
        case .highestQuality: "Highest quality"
        }
    }

    private var writingBehaviorSection: some View {
        PanelSection(legend: "Automatic writing") {
            Plate {
                VStack(spacing: 0) {
                    PanelSwitch(
                        legend: "Professional Email mode",
                        detail: "Formats complete dictation in Mail and consented Gmail.",
                        isOn: writingBoolBinding(\.emailModeEnabled)
                    )
                    ScribeRule()
                    PanelSwitch(
                        legend: "Mail",
                        detail: "Apply Email mode in Apple Mail.",
                        isOn: mailEnabledBinding
                    )
                    ScribeRule()
                    PanelSwitch(
                        legend: "Gmail",
                        detail: "Classify mail.google.com locally in supported browsers.",
                        isOn: gmailEnabledBinding
                    )
                    if environment.settings.writing.route.isRemote {
                        ScribeRule()
                        PanelSwitch(
                            legend: "Send completed Email text",
                            detail: "Sends the complete repaired transcript, writing instruction, and Email category. Never audio, URL, clipboard, History, or nearby text.",
                            isOn: writingBoolBinding(\.remoteEmailTextAllowed)
                        )
                        ScribeRule()
                        PanelSwitch(
                            legend: "Send selected Command text",
                            detail: "Only for explicit Command mode; includes the selection and spoken instruction.",
                            isOn: writingBoolBinding(\.remoteSelectedTextAllowed)
                        )
                    }
                    ScribeRule()
                    Text("Cloud providers may retain data under your provider and account policy. Murmur requests store=false, hosts nothing, and never falls back to another provider.")
                        .font(MurmurFace.body(10.5))
                        .foregroundStyle(MurmurTheme.Engraving.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var writingRouteBinding: Binding<WritingTransformationRoute> {
        Binding(
            get: { environment.settings.writing.route },
            set: { route in environment.updateSettings { $0.writing.route = route } }
        )
    }

    private func writingBoolBinding(_ keyPath: WritableKeyPath<WritingSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { environment.settings.writing[keyPath: keyPath] },
            set: { value in environment.updateSettings { $0.writing[keyPath: keyPath] = value } }
        )
    }

    private var mailEnabledBinding: Binding<Bool> {
        applicationWritingBinding(bundleIdentifiers: ["com.apple.mail"])
    }

    private var gmailEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                environment.settings.writing.browserDomainDetectionAllowed
                    && environment.settings.writing.disabledApplicationBundleIdentifiers.isDisjoint(
                        with: BrowserDomainContext.supportedBundleIdentifiers
                    )
            },
            set: { enabled in
                environment.updateSettings { settings in
                    settings.writing.browserDomainDetectionAllowed = enabled
                    if enabled {
                        settings.writing.disabledApplicationBundleIdentifiers.subtract(
                            BrowserDomainContext.supportedBundleIdentifiers
                        )
                    } else {
                        settings.writing.disabledApplicationBundleIdentifiers.formUnion(
                            BrowserDomainContext.supportedBundleIdentifiers
                        )
                    }
                }
            }
        )
    }

    private func applicationWritingBinding(bundleIdentifiers: Set<String>) -> Binding<Bool> {
        Binding(
            get: {
                environment.settings.writing.disabledApplicationBundleIdentifiers
                    .isDisjoint(with: bundleIdentifiers)
            },
            set: { enabled in
                environment.updateSettings { settings in
                    if enabled {
                        settings.writing.disabledApplicationBundleIdentifiers.subtract(bundleIdentifiers)
                    } else {
                        settings.writing.disabledApplicationBundleIdentifiers.formUnion(bundleIdentifiers)
                    }
                }
            }
        )
    }

    private func manifests(for language: WhisperModelLanguage) -> [WhisperDownloadManifest] {
        WhisperDownloadManifest.supported.filter { $0.language == language }
    }

    // MARK: Rows

    @ViewBuilder
    private func modelRow(_ manifest: WhisperDownloadManifest) -> some View {
        let isInstalled = installedIdentifiers.contains(manifest.id)
        let isActive = isInstalled && environment.settings.preferredWhisperModelIdentifier == manifest.id

        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
            HStack(alignment: .top, spacing: MurmurTheme.Space.medium) {
                Lamp(colour: .verify, isLit: isActive)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: MurmurTheme.Space.small) {
                        Text(manifest.displayName)
                            .font(MurmurFace.body(13, weight: .medium))
                            .foregroundStyle(MurmurTheme.Engraving.ink)
                        if manifest.isRecommended {
                            Legend("Recommended", size: .micro, color: MurmurTheme.Engraving.tertiary)
                        }
                    }
                    Text(manifest.qualityDescription)
                        .font(MurmurFace.body(11.5))
                        .foregroundStyle(MurmurTheme.Engraving.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: MurmurTheme.Space.medium)

                // Fixed column widths so the specs read down the page as a real
                // specification table rather than drifting with each row's word length.
                HStack(spacing: MurmurTheme.Space.medium) {
                    SpecValue(value: manifest.speed.rawValue, width: 62)
                    SpecValue(value: "\(manifest.quality)", width: 74)
                    SpecValue(value: Self.formattedSize(manifest.byteCount), width: 68)
                }
                .padding(.top, 2)

                modelAction(manifest, isInstalled: isInstalled, isActive: isActive)
            }

            if case .downloading(let active) = installer.state, active.id == manifest.id {
                transferStatus(progress: installer.progress, paused: false)
            } else if case .paused(let active) = installer.state, active.id == manifest.id {
                transferStatus(progress: installer.progress, paused: true)
            } else if case .verifying(let active) = installer.state, active.id == manifest.id {
                HStack(spacing: MurmurTheme.Space.small) {
                    Lamp(colour: .caution, isLit: true)
                    Legend("Verifying checksum", size: .micro, color: MurmurTheme.Engraving.secondary)
                }
                .padding(.leading, 19)
            }
        }
        .padding(.horizontal, MurmurTheme.Space.large)
        .padding(.vertical, MurmurTheme.Space.medium)
    }

    @ViewBuilder
    private func modelAction(
        _ manifest: WhisperDownloadManifest,
        isInstalled: Bool,
        isActive: Bool
    ) -> some View {
        if isInstalled {
            HStack(spacing: MurmurTheme.Space.small) {
                if isActive {
                    Legend("Active", size: .micro, color: MurmurTheme.Lamp.verify)
                } else {
                    Button("Use") { environment.activateWhisperModel(identifier: manifest.id) }
                        .buttonStyle(PanelButtonStyle(rank: .secondary))
                }
                Button {
                    removalError = nil
                    pendingRemoval = manifest
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MurmurTheme.Engraving.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(manifest.displayName)")
                .help("Delete this model from this Mac")
            }
        } else if case .downloading(let active) = installer.state, active.id == manifest.id {
            HStack(spacing: 5) {
                Button("Pause") { installer.pause() }.buttonStyle(PanelButtonStyle(rank: .secondary))
                Button("Cancel") { installer.cancel() }.buttonStyle(PanelButtonStyle(rank: .secondary))
            }
        } else if case .paused(let active) = installer.state, active.id == manifest.id {
            HStack(spacing: 5) {
                Button("Resume") { installer.resume() }.buttonStyle(PanelButtonStyle(rank: .secondary))
                Button("Cancel") { installer.cancel() }.buttonStyle(PanelButtonStyle(rank: .secondary))
            }
        } else if case .verifying(let active) = installer.state, active.id == manifest.id {
            ProgressView().controlSize(.small)
        } else {
            // Secondary, not primary: seven filled slabs down one page would make
            // installing look like the page's purpose. Reading the specs is.
            Button("Install") { installer.install(manifest) }
                .buttonStyle(PanelButtonStyle(rank: .secondary))
                .disabled(isInstallerBusy)
        }
    }

    private func transferStatus(progress: Double, paused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TransferBar(progress: progress)
            HStack {
                Legend("\(paused ? "Paused" : "Downloading") · \(Self.formattedSize(installer.downloadedBytes)) of \(Self.formattedSize(installer.expectedBytes))", size: .micro, color: MurmurTheme.Engraving.secondary)
                Spacer()
                if paused == false, installer.bytesPerSecond > 0 {
                    let remaining = Double(max(installer.expectedBytes - installer.downloadedBytes, 0))
                    Legend("\(Self.formattedSize(Int64(installer.bytesPerSecond)))/s · \(Self.formattedDuration(remaining / installer.bytesPerSecond)) left", size: .micro, color: MurmurTheme.Engraving.tertiary)
                }
            }
            .padding(.leading, 19)
        }
    }

    // MARK: Derived state

    private var fault: String? {
        if let removalError { return removalError }
        if case .failed(let message) = installer.state { return message }
        return nil
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
        case .idle, .paused, .installed, .failed:
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

    private static func formattedDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let value = max(Int(seconds.rounded()), 0)
        return value >= 60 ? "\(value / 60)m \(value % 60)s" : "\(value)s"
    }
}

// MARK: - Parts

private struct SpecValue: View {
    let value: String
    var width: CGFloat

    var body: some View {
        Text(value)
            .font(MurmurFace.readout(10.5))
            .monospacedDigit()
            .foregroundStyle(MurmurTheme.Engraving.secondary)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }
}

/// A determinate transfer against a recessed track. Verification is a separate, named
/// state, because a checksum that has not finished is not a download that has.
private struct TransferBar: View {
    let progress: Double

    var body: some View {
        HStack(spacing: MurmurTheme.Space.medium) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(MurmurTheme.Finish.recess)
                    Rectangle()
                        .fill(MurmurTheme.Engraving.ink)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: 4)
            .overlay(
                Rectangle()
                    .strokeBorder(MurmurTheme.Engraving.scribe, lineWidth: MurmurTheme.Space.hairline)
            )

            Text("\(Int(progress * 100))%")
                .font(MurmurFace.readout(10))
                .monospacedDigit()
                .foregroundStyle(MurmurTheme.Engraving.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.leading, 19)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Downloading, \(Int(progress * 100)) percent")
    }
}

private struct FaultPlate: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: MurmurTheme.Space.medium) {
            Lamp(colour: .caution, isLit: true)
                .padding(.top, 3)
            Text(message)
                .font(MurmurFace.body(12))
                .foregroundStyle(MurmurTheme.Engraving.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(MurmurTheme.Space.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.plate, style: .continuous)
                .fill(MurmurTheme.Finish.plate)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.plate, style: .continuous)
                .strokeBorder(MurmurTheme.Lamp.caution.opacity(0.5), lineWidth: MurmurTheme.Space.hairline)
        )
    }
}
