import SwiftUI

private enum AppTheme {
    static let background = Color(red: 0.055, green: 0.058, blue: 0.064)
    static let panel = Color(red: 0.095, green: 0.10, blue: 0.112)
    static let elevatedPanel = Color(red: 0.12, green: 0.126, blue: 0.14)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.62)
    static let hairline = Color.white.opacity(0.08)
    static let accent = Color.white.opacity(0.9)
    static let softShadow = Color.black.opacity(0.24)
}

struct HubRootView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $coordinator.selectedSidebar) { destination in
                Label(destination.title, systemImage: icon(for: destination))
                    .tag(destination)
            }
            .listStyle(.sidebar)
            .navigationTitle("Murmur")
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
                .buttonStyle(DarkButtonStyle())
        }
        .tint(AppTheme.accent)
    }

    @ViewBuilder
    private var detailView: some View {
        switch coordinator.selectedSidebar {
        case .dashboard:
            DashboardView(coordinator: coordinator)
        case .history:
            HistoryView(entries: coordinator.historyStore.entries)
        case .snippets:
            SnippetsView(store: coordinator.personalizationStore)
        case .dictionary:
            DictionaryView(store: coordinator.personalizationStore)
        case .styles:
            StyleProfilesView(store: coordinator.personalizationStore)
        case .notes:
            NotesOverviewView(coordinator: coordinator)
        case .models:
            ModelsView(coordinator: coordinator)
        case .settings:
            SettingsSceneView(coordinator: coordinator)
        }
    }

    private func icon(for destination: SidebarDestination) -> String {
        switch destination {
        case .dashboard:
            "speedometer"
        case .history:
            "clock.arrow.circlepath"
        case .snippets:
            "text.append"
        case .dictionary:
            "character.book.closed"
        case .styles:
            "paintbrush"
        case .notes:
            "note.text"
        case .models:
            "cpu"
        case .settings:
            "gearshape"
        }
    }
}

struct MenuBarRootView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Open Hub") {
                coordinator.presentHubWindow()
                openWindow(id: "hub")
            }
            Button("Toggle Hands Free") {
                coordinator.sessionManager.toggleHandsFree()
            }
            Button("Open Scratchpad") {
                openWindow(id: "scratchpad")
            }
            Divider()
            Button("Export Redacted Diagnostics") {
                coordinator.exportDiagnostics(redactingContent: true)
            }
            Divider()
            Button("Quit Murmur") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
    }
}

struct DashboardView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dashboardHeader
                HStack(alignment: .top, spacing: 16) {
                    statusCard
                    permissionCard
                }
                HStack(alignment: .top, spacing: 16) {
                    controlsCard
                    statsCard
                }
                if let lastError = coordinator.sessionManager.lastError {
                    MessageCard(title: "Latest Issue", message: lastError, tint: .red)
                }
                hotkeysCard
                notesShortcutCard(openWindow: openWindow)
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Talk naturally. Write cleanly.")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("Local dictation controls, runtime health, and recent writing activity.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(AppTheme.primaryText)
                        .frame(width: 4, height: CGFloat([10, 18, 14, 22, 12][index]))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.elevatedPanel, in: Capsule())
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.hairline)
        }
    }

    private var statusCard: some View {
        DashboardCard(title: "Dictation State", icon: "waveform.and.mic") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Phase", value: coordinator.sessionManager.phase.rawValue.capitalized)
                LabeledContent("Mode", value: coordinator.sessionManager.activeMode?.title ?? "Idle")
                LabeledContent("Context", value: coordinator.sessionManager.currentApp.writingContext.title)
                LabeledContent("App", value: coordinator.sessionManager.currentApp.localizedName)
                if coordinator.sessionManager.partialTranscript.isEmpty == false {
                    Text(coordinator.sessionManager.partialTranscript)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                if coordinator.sessionManager.lastCommittedText.isEmpty == false {
                    Divider()
                    Text(coordinator.sessionManager.lastCommittedText)
                        .font(.body)
                }
            }
        }
    }

    private var permissionCard: some View {
        DashboardCard(title: "Permissions", icon: "hand.raised") {
            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(name: "Microphone", granted: coordinator.permissionCenter.permissions.microphoneGranted)
                PermissionRow(name: "Speech Recognition", granted: coordinator.permissionCenter.permissions.speechRecognitionGranted)
                PermissionRow(name: "Accessibility", granted: coordinator.permissionCenter.permissions.accessibilityGranted)
                HStack {
                    Button(coordinator.permissionCenter.isRequestingAccess ? "Requesting…" : "Request Required Access") {
                        Task {
                            await coordinator.requestRequiredPermissions()
                        }
                    }
                    .disabled(coordinator.permissionCenter.isRequestingAccess)
                    Button("Open Privacy Settings") {
                        coordinator.permissionCenter.openPrivacySettings()
                    }
                }
                Text("Accessibility still requires approving Murmur in System Settings after macOS shows the prompt.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var controlsCard: some View {
        DashboardCard(title: "Controls", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Start Push To Talk") {
                        coordinator.sessionManager.beginPushToTalk()
                    }
                    Button("Stop") {
                        coordinator.sessionManager.endPushToTalk()
                    }
                    .disabled(coordinator.sessionManager.activeMode == nil)
                }
                HStack {
                    Button("Toggle Hands Free") {
                        coordinator.sessionManager.toggleHandsFree()
                    }
                    Button("Command Mode") {
                        coordinator.sessionManager.beginCommandMode()
                    }
                }
                Text("The app also listens for the global shortcuts defined in Settings and the dashboard.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var statsCard: some View {
        let stats = coordinator.historyStore.stats
        return DashboardCard(title: "Usage", icon: "chart.bar") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Sessions", value: "\(stats.totalSessions)")
                LabeledContent("Words Dictated", value: "\(stats.totalWords)")
                LabeledContent("Average WPM", value: String(format: "%.0f", stats.averageWordsPerMinute))
                if let lastSessionAt = stats.lastSessionAt {
                    LabeledContent("Last Session", value: lastSessionAt.formatted(date: .abbreviated, time: .shortened))
                }
                HStack {
                    Button("Export Redacted Diagnostics") {
                        coordinator.exportDiagnostics(redactingContent: true)
                    }
                    Button("Export Full Diagnostics") {
                        coordinator.exportDiagnostics(redactingContent: false)
                    }
                }
            }
        }
    }

    private var hotkeysCard: some View {
        DashboardCard(title: "Default Hotkeys", icon: "keyboard") {
            VStack(alignment: .leading, spacing: 10) {
                HotkeyRow(shortcut: coordinator.settingsStore.snapshot.pushToTalkShortcut)
                HotkeyRow(shortcut: coordinator.settingsStore.snapshot.handsFreeShortcut)
                HotkeyRow(shortcut: coordinator.settingsStore.snapshot.commandShortcut)
            }
        }
    }

    private func notesShortcutCard(openWindow: OpenWindowAction) -> some View {
        DashboardCard(title: "Scratchpad", icon: "square.and.pencil") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Use the scratchpad as a local landing zone for dictated notes, command-mode experiments, and quick drafts.")
                    .foregroundStyle(AppTheme.secondaryText)
                Button("Open Scratchpad") {
                    openWindow(id: "scratchpad")
                }
            }
        }
    }
}

struct HistoryView: View {
    let entries: [HistoryEntry]

    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.sourceAppName)
                        .font(.headline)
                    Spacer()
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                Text(entry.finalText)
                    .font(.body)
                Text("\(entry.mode.title) • \(entry.appContext.title) • \(entry.insertionOutcome.method.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("History")
    }
}

struct SnippetsView: View {
    @ObservedObject var store: PersonalizationStore
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                TextField("Trigger", text: $trigger)
                TextField("Expansion", text: $expansion, axis: .vertical)
                Button("Add Snippet") {
                    guard !trigger.isEmpty, !expansion.isEmpty else { return }
                    store.addSnippet(trigger: trigger, expansion: expansion)
                    trigger = ""
                    expansion = ""
                }
            }
            List {
                ForEach(store.snapshot.snippets) { snippet in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(snippet.trigger)
                                .font(.headline)
                            Text(snippet.expansion)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Delete", role: .destructive) {
                            store.removeSnippet(snippet)
                        }
                    }
                }
            }
        }
        .padding(24)
        .navigationTitle("Snippets")
    }
}

struct DictionaryView: View {
    @ObservedObject var store: PersonalizationStore
    @State private var phrase = ""
    @State private var replacement = ""
    @State private var context: AppWritingContext = .unknown

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                TextField("Phrase", text: $phrase)
                TextField("Replacement", text: $replacement)
                Picker("Context", selection: $context) {
                    Text("All Contexts").tag(AppWritingContext.unknown)
                    ForEach(AppWritingContext.allCases.filter { $0 != .unknown }) { context in
                        Text(context.title).tag(context)
                    }
                }
                Button("Add Dictionary Entry") {
                    guard !phrase.isEmpty, !replacement.isEmpty else { return }
                    store.addDictionaryEntry(
                        phrase: phrase,
                        replacement: replacement,
                        context: context == .unknown ? nil : context
                    )
                    phrase = ""
                    replacement = ""
                    context = .unknown
                }
            }
            List(store.snapshot.dictionaryEntries) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.phrase)
                            .font(.headline)
                        Text(entry.replacement)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.context?.title ?? "All")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Delete", role: .destructive) {
                        store.removeDictionaryEntry(entry)
                    }
                }
            }
        }
        .padding(24)
        .navigationTitle("Dictionary")
    }
}

struct StyleProfilesView: View {
    @ObservedObject var store: PersonalizationStore

    var body: some View {
        List(store.snapshot.styleProfiles) { profile in
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.name)
                    .font(.headline)
                Text(profile.context.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(profile.instructions)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Style Profiles")
    }
}

struct NotesOverviewView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Open Scratchpad") {
                    openWindow(id: "scratchpad")
                }
                Button("New Note") {
                    coordinator.notesStore.createNote()
                }
            }
            List(coordinator.notesStore.notes) { note in
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title)
                        .font(.headline)
                    Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(note.body)
                        .lineLimit(3)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
        .navigationTitle("Notes")
    }
}

struct ModelsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var modelManager: ModelManager
    @ObservedObject private var runtimeInstaller: RuntimeInstaller

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _modelManager = ObservedObject(wrappedValue: coordinator.modelManager)
        _runtimeInstaller = ObservedObject(wrappedValue: coordinator.runtimeInstaller)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                currentActivityCard
                runtimeInstallersCard
                whisperModelsCard
                llamaModelsCard
            }
            .padding(24)
        }
        .navigationTitle("Models")
    }

    @ViewBuilder
    private var currentActivityCard: some View {
        if runtimeInstaller.runtimeProgress != nil || runtimeInstaller.whisperModelProgress != nil || runtimeInstaller.llamaModelProgress != nil {
            DashboardCard(title: "Current Activity", icon: "arrow.triangle.2.circlepath") {
                VStack(alignment: .leading, spacing: 12) {
                    if let progress = runtimeInstaller.runtimeProgress {
                        progressView(progress)
                        Button("Cancel Runtime Install", role: .destructive) {
                            coordinator.cancelRuntimeInstall()
                        }
                    }
                    if let progress = runtimeInstaller.whisperModelProgress {
                        progressView(progress)
                        Button("Cancel Whisper Model Install", role: .destructive) {
                            coordinator.cancelWhisperModelInstall()
                        }
                    }
                    if let progress = runtimeInstaller.llamaModelProgress {
                        progressView(progress)
                        Button("Cancel Llama Model Install", role: .destructive) {
                            coordinator.cancelLlamaModelInstall()
                        }
                    }
                }
            }
        }
    }

    private var runtimeInstallersCard: some View {
        DashboardCard(title: "Runtime Installers", icon: "shippingbox") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Refresh PATH Checks") {
                        coordinator.refreshRuntimeInventory()
                    }
                    Text("Uses normal `which` checks such as `which whisper-cli` and `which llama-cli`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(modelManager.runtimes) { runtime in
                    runtimeRow(runtime)
                    if runtime.detectionSource == .path {
                        Text("Detected on PATH. This button builds an app-managed copy; it does not modify the PATH-installed binary.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if runtimeInstaller.activeRuntime == runtime.kind, let progress = runtimeInstaller.runtimeProgress {
                        progressView(progress)
                    }
                    Divider()
                }
            }
        }
    }

    private var whisperModelsCard: some View {
        DashboardCard(title: "Whisper Models", icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Import Whisper GGML File") {
                        coordinator.importWhisperModel()
                    }
                    Text("Installs official whisper.cpp model files into \(AppPaths.whisperModelsDirectory.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(modelManager.whisperModels()) { descriptor in
                    whisperModelRow(descriptor)
                    Divider()
                }
            }
        }
    }

    private var llamaModelsCard: some View {
        DashboardCard(title: "Llama Models", icon: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Import Llama GGUF File") {
                        coordinator.importLlamaModel()
                    }
                    Text("Downloads curated GGUF models into \(AppPaths.llamaModelsDirectory.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(modelManager.llamaModels()) { descriptor in
                    llamaModelRow(descriptor)
                    Divider()
                }
            }
        }
    }

    private func runtimeRow(_ runtime: RuntimeInstallation) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(runtime.kind.rawValue)
                    .font(.headline)
                Text(runtime.notes)
                    .foregroundStyle(.secondary)
                if let installPath = runtime.installPath {
                    Text(installPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Detection: \(runtime.detectionSource.rawValue.capitalized)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(runtime.installState.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(runtimeButtonTitle(for: runtime)) {
                    coordinator.installRuntime(runtime.kind)
                }
                .disabled(runtimeInstaller.activeRuntime != nil)
                if runtimeInstaller.activeRuntime == runtime.kind {
                    Button("Cancel", role: .destructive) {
                        coordinator.cancelRuntimeInstall()
                    }
                }
            }
        }
    }

    private func whisperModelRow(_ descriptor: ModelDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            modelDescriptorRow(descriptor, recommendedIdentifier: WhisperModelPreset.recommended.rawValue) {
                if let identifier = descriptor.modelIdentifier,
                   let preset = WhisperModelPreset(rawValue: identifier) {
                    whisperModelActions(descriptor: descriptor, preset: preset, identifier: identifier)
                }
            }
            if let identifier = descriptor.modelIdentifier,
               let preset = WhisperModelPreset(rawValue: identifier),
               runtimeInstaller.activeWhisperModel == preset,
               let progress = runtimeInstaller.whisperModelProgress {
                progressView(progress)
            }
        }
    }

    private func llamaModelRow(_ descriptor: ModelDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            modelDescriptorRow(descriptor, recommendedIdentifier: LlamaModelPreset.recommended.rawValue) {
                if let identifier = descriptor.modelIdentifier,
                   let preset = LlamaModelPreset(rawValue: identifier) {
                    llamaModelActions(descriptor: descriptor, preset: preset, identifier: identifier)
                }
            }
            if let identifier = descriptor.modelIdentifier,
               let preset = LlamaModelPreset(rawValue: identifier),
               runtimeInstaller.activeLlamaModel == preset,
               let progress = runtimeInstaller.llamaModelProgress {
                progressView(progress)
            }
        }
    }

    private func modelDescriptorRow<Actions: View>(
        _ descriptor: ModelDescriptor,
        recommendedIdentifier: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(descriptor.name)
                    .font(.headline)
                if descriptor.modelIdentifier == recommendedIdentifier {
                    Text("Recommended default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(descriptor.notes)
                    .foregroundStyle(.secondary)
                if let localeIdentifier = descriptor.localeIdentifier {
                    Text(localeIdentifier == "en_US" ? "English-only" : localeIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if descriptor.runtime == .whisperCPP {
                    Text("Multilingual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let storagePath = descriptor.storagePath {
                    Text(storagePath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(descriptor.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                actions()
            }
        }
    }

    @ViewBuilder
    private func whisperModelActions(descriptor: ModelDescriptor, preset: WhisperModelPreset, identifier: String) -> some View {
        if isUsable(descriptor), coordinator.settingsStore.snapshot.preferredWhisperModelIdentifier == identifier {
            selectedBadge
        } else {
            Button("Use Model") {
                coordinator.settingsStore.update { $0.preferredWhisperModelIdentifier = identifier }
            }
            .disabled(isUsable(descriptor) == false)
        }

        if runtimeInstaller.activeWhisperModel == preset {
            Button("Cancel", role: .destructive) {
                coordinator.cancelWhisperModelInstall()
            }
        } else {
            Button(descriptor.status == .ready || descriptor.status == .imported ? "Reinstall" : "Install") {
                coordinator.installWhisperModel(preset)
            }
            .disabled(runtimeInstaller.activeWhisperModel != nil || runtimeInstaller.activeLlamaModel != nil)
        }

        if canDelete(descriptor) {
            Button("Delete", role: .destructive) {
                coordinator.deleteWhisperModel(preset)
            }
            .disabled(runtimeInstaller.activeWhisperModel != nil || runtimeInstaller.activeLlamaModel != nil)
        }
    }

    @ViewBuilder
    private func llamaModelActions(descriptor: ModelDescriptor, preset: LlamaModelPreset, identifier: String) -> some View {
        if isUsable(descriptor), coordinator.settingsStore.snapshot.preferredLlamaModelIdentifier == identifier {
            selectedBadge
        } else {
            Button("Use Model") {
                coordinator.settingsStore.update { $0.preferredLlamaModelIdentifier = identifier }
            }
            .disabled(isUsable(descriptor) == false)
        }

        if runtimeInstaller.activeLlamaModel == preset {
            Button("Cancel", role: .destructive) {
                coordinator.cancelLlamaModelInstall()
            }
        } else {
            Button(descriptor.status == .ready || descriptor.status == .imported ? "Reinstall" : "Install") {
                coordinator.installLlamaModel(preset)
            }
            .disabled(runtimeInstaller.activeLlamaModel != nil || runtimeInstaller.activeWhisperModel != nil)
        }

        if canDelete(descriptor) {
            Button("Delete", role: .destructive) {
                coordinator.deleteLlamaModel(preset)
            }
            .disabled(runtimeInstaller.activeLlamaModel != nil || runtimeInstaller.activeWhisperModel != nil)
        }
    }

    private func runtimeButtonTitle(for runtime: RuntimeInstallation) -> String {
        if runtimeInstaller.activeRuntime == runtime.kind {
            return "Working…"
        }
        switch runtime.detectionSource {
        case .path:
            return "Build Managed Copy"
        case .managed:
            return runtime.installState == .installed ? "Update Managed Copy" : "Install Managed Copy"
        case .unknown:
            return runtime.installState == .installed ? "Update" : "Install"
        }
    }

    private func isUsable(_ descriptor: ModelDescriptor) -> Bool {
        descriptor.status == .ready || descriptor.status == .imported
    }

    private func canDelete(_ descriptor: ModelDescriptor) -> Bool {
        isUsable(descriptor) && descriptor.storagePath != nil
    }

    @ViewBuilder
    private func progressView(_ progress: TaskProgressState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(progress.title)
                .font(.caption.weight(.semibold))
            if let fractionCompleted = progress.fractionCompleted {
                ProgressView(value: fractionCompleted)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            Text(progress.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedBadge: some View {
        Text("Selected")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.green.opacity(0.15), in: Capsule())
            .foregroundStyle(.green)
    }
}

struct ScratchpadWindowView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        NavigationSplitView {
            List(
                coordinator.notesStore.notes,
                selection: Binding(
                    get: { coordinator.notesStore.selectedNoteID },
                    set: { coordinator.notesStore.selectedNoteID = $0 }
                )
            ) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .lineLimit(1)
                    Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(note.id)
            }
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        coordinator.notesStore.createNote()
                    } label: {
                        Label("New Note", systemImage: "plus")
                    }
                }
            }
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                if let note = coordinator.notesStore.selectedNote {
                    Text(note.title)
                        .font(.title2.weight(.semibold))
                    TextEditor(text: Binding(
                        get: { coordinator.notesStore.selectedNote?.body ?? "" },
                        set: { coordinator.notesStore.updateSelected(body: $0) }
                    ))
                    .font(.body.monospaced())
                } else {
                    ContentUnavailableView("No Note Selected", systemImage: "note.text", description: Text("Create a note to start dictating into the scratchpad."))
                }
            }
            .padding(20)
        }
    }
}

struct SettingsSceneView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Form {
            Picker("Cleanup Level", selection: Binding(
                get: { coordinator.settingsStore.snapshot.cleanupLevel },
                set: { newValue in
                    coordinator.settingsStore.update { $0.cleanupLevel = newValue }
                }
            )) {
                ForEach(CleanupLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }

            TextField("Locale Identifier", text: Binding(
                get: { coordinator.settingsStore.snapshot.localeIdentifier },
                set: { newValue in
                    coordinator.settingsStore.update { $0.localeIdentifier = newValue }
                }
            ))

            Toggle("Retain raw audio history", isOn: Binding(
                get: { coordinator.settingsStore.snapshot.retainAudioHistory },
                set: { newValue in
                    coordinator.settingsStore.update { $0.retainAudioHistory = newValue }
                }
            ))

            Section("Hotkeys") {
                HotkeyRow(shortcut: coordinator.settingsStore.snapshot.pushToTalkShortcut)
                HotkeyRow(shortcut: coordinator.settingsStore.snapshot.handsFreeShortcut)
                HotkeyRow(shortcut: coordinator.settingsStore.snapshot.commandShortcut)
            }
        }
        .padding(24)
        .navigationTitle("Settings")
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
            content
                .foregroundStyle(AppTheme.primaryText)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.hairline)
        }
        .shadow(color: AppTheme.softShadow, radius: 16, y: 8)
    }
}

private struct PermissionRow: View {
    let name: String
    let granted: Bool

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? AppTheme.primaryText : .red)
        }
    }
}

private struct HotkeyRow: View {
    let shortcut: HotkeyShortcut

    var body: some View {
        HStack {
            Text(shortcut.displayName)
                .font(.headline)
            Spacer()
            Text(shortcut.detail)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }
}

private struct MessageCard: View {
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)
            Text(message)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.28))
        }
    }
}

private struct DarkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.black.opacity(0.9) : AppTheme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isEnabled ? AppTheme.accent : AppTheme.elevatedPanel)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
