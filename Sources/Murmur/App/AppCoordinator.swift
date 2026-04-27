import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class DictationSessionManager: ObservableObject {
    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var activeMode: DictationMode?
    @Published private(set) var partialTranscript = ""
    @Published private(set) var lastCommittedText = ""
    @Published private(set) var currentApp = FrontmostAppDescriptor(localizedName: "Unknown App", bundleIdentifier: "unknown.bundle", writingContext: .unknown)
    @Published private(set) var audioLevel: Double = -80
    @Published var lastError: String?
    @Published private(set) var lastInsertionOutcome: InsertionOutcome = .unavailable
    @Published private(set) var latestSession: DictationSession?

    private let audioCaptureService: AudioCaptureServiceProtocol
    private let transcriptionEngine: TranscriptionEngine
    private let transformEngine: TransformEngine
    private let formatterPipeline: FormatterPipeline
    private let insertionCoordinator: AXInsertionCoordinator
    private let contextClassifier: AppContextClassifier
    private let personalizationStore: PersonalizationStore
    private let historyStore: HistoryStore
    private let settingsStore: SettingsStore
    private let permissionCenter: PermissionCenter
    private let floatingBarController: FloatingBarController

    private var pendingSession = DictationSession(
        id: UUID(),
        mode: .pushToTalk,
        appContext: .unknown,
        sourceAppBundleID: "unknown.bundle",
        localeIdentifier: Locale.autoupdatingCurrent.identifier,
        startedAt: Date(),
        endedAt: nil,
        audioMetrics: .zero,
        partialTranscript: "",
        finalTranscript: "",
        insertionOutcome: .pending,
        commandApplied: nil
    )

    private var speechObserved = false
    private var lastVoiceActivity = Date()
    private var finalizationFallbackTask: Task<Void, Never>?
    private var finalizedSessionID: UUID?

    init(
        audioCaptureService: AudioCaptureServiceProtocol,
        transcriptionEngine: TranscriptionEngine,
        transformEngine: TransformEngine,
        formatterPipeline: FormatterPipeline,
        insertionCoordinator: AXInsertionCoordinator,
        contextClassifier: AppContextClassifier,
        personalizationStore: PersonalizationStore,
        historyStore: HistoryStore,
        settingsStore: SettingsStore,
        permissionCenter: PermissionCenter,
        floatingBarController: FloatingBarController
    ) {
        self.audioCaptureService = audioCaptureService
        self.transcriptionEngine = transcriptionEngine
        self.transformEngine = transformEngine
        self.formatterPipeline = formatterPipeline
        self.insertionCoordinator = insertionCoordinator
        self.contextClassifier = contextClassifier
        self.personalizationStore = personalizationStore
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        self.permissionCenter = permissionCenter
        self.floatingBarController = floatingBarController
    }

    func beginPushToTalk() {
        startSession(mode: .pushToTalk)
    }

    func endPushToTalk() {
        stopListeningIfNeeded()
    }

    func toggleHandsFree() {
        if phase == .listening, activeMode == .handsFree {
            stopListeningIfNeeded()
        } else {
            startSession(mode: .handsFree)
        }
    }

    func beginCommandMode() {
        startSession(mode: .command)
    }

    func endCommandMode() {
        stopListeningIfNeeded()
    }

    private func startSession(mode: DictationMode) {
        guard phase != .listening, phase != .processing else { return }
        permissionCenter.refresh()
        let permissions = permissionCenter.permissions
        guard permissions.microphoneGranted, permissions.speechRecognitionGranted, permissions.accessibilityGranted else {
            failSession("Grant microphone, speech recognition, and accessibility permissions before dictating.")
            return
        }

        currentApp = contextClassifier.currentApp()
        activeMode = mode
        phase = .listening
        partialTranscript = ""
        lastCommittedText = ""
        audioLevel = -80
        lastError = nil
        lastInsertionOutcome = .pending
        finalizedSessionID = nil
        speechObserved = false
        lastVoiceActivity = Date()
        pendingSession = DictationSession(
            id: UUID(),
            mode: mode,
            appContext: currentApp.writingContext,
            sourceAppBundleID: currentApp.bundleIdentifier,
            localeIdentifier: settingsStore.snapshot.localeIdentifier,
            startedAt: Date(),
            endedAt: nil,
            audioMetrics: .zero,
            partialTranscript: "",
            finalTranscript: "",
            insertionOutcome: .pending,
            commandApplied: nil
        )

        floatingBarController.show(
            mode: mode,
            phase: .listening,
            transcriptText: "Listening…",
            audioLevel: audioLevel,
            context: currentApp.writingContext,
            anchorFrame: insertionCoordinator.floatingAnchorFrame()
        )

        do {
            try transcriptionEngine.startTranscribing(
                localeIdentifier: settingsStore.snapshot.localeIdentifier,
                partialHandler: { [weak self] text in
                    Task { @MainActor in
                        self?.handlePartialTranscript(text)
                    }
                },
                completion: { [weak self] result in
                    Task { @MainActor in
                        self?.handleTranscriptionCompletion(result)
                    }
                }
            )
            try audioCaptureService.startCapture(
                bufferHandler: { [weak self] buffer, _ in
                    self?.transcriptionEngine.append(buffer)
                },
                levelHandler: { [weak self] level in
                    Task { @MainActor in
                        self?.handleAudioLevel(level)
                    }
                }
            )
        } catch {
            failSession(error.localizedDescription)
        }
    }

    private func stopListeningIfNeeded() {
        guard phase == .listening else { return }
        phase = .processing
        pendingSession.audioMetrics = audioCaptureService.stopCapture()
        pendingSession.partialTranscript = partialTranscript
        floatingBarController.update(phase: .processing, transcriptText: partialTranscript.nonEmpty ?? "Processing…", audioLevel: audioLevel)
        transcriptionEngine.finish()

        finalizationFallbackTask?.cancel()
        finalizationFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.phase == .processing else { return }
            let transcript = self.partialTranscript.nonEmpty ?? self.transcriptionEngine.latestTranscript
            if let transcript = self.normalizedSubstantiveTranscript(transcript) {
                await self.commitTranscript(transcript)
            } else {
                self.finishSessionWithoutInsertion()
            }
        }
    }

    private func handleAudioLevel(_ level: Double) {
        audioLevel = level
        if phase == .listening {
            floatingBarController.update(audioLevel: level)
        }
        if level > -42 {
            speechObserved = true
            lastVoiceActivity = Date()
        } else if activeMode == .handsFree,
                  phase == .listening,
                  speechObserved,
                  Date().timeIntervalSince(lastVoiceActivity) > 1.1,
                  partialTranscript.nonEmpty != nil {
            stopListeningIfNeeded()
        }
    }

    private func handlePartialTranscript(_ text: String) {
        partialTranscript = text
        pendingSession.partialTranscript = text
        floatingBarController.update(transcriptText: text, audioLevel: audioLevel)
    }

    private func handleTranscriptionCompletion(_ result: Result<String, Error>) {
        finalizationFallbackTask?.cancel()
        switch result {
        case .success(let transcript):
            Task { @MainActor in
                guard let transcript = normalizedSubstantiveTranscript(transcript.nonEmpty ?? partialTranscript) else {
                    finishSessionWithoutInsertion()
                    return
                }
                await commitTranscript(transcript)
            }
        case .failure(let error):
            failSession(error.localizedDescription)
        }
    }

    private func commitTranscript(_ transcript: String) async {
        guard let resolved = normalizedSubstantiveTranscript(transcript) else {
            finishSessionWithoutInsertion()
            return
        }
        guard claimFinalizationForCurrentSession() else { return }

        let style = personalizationStore.snapshot.styleProfiles.first(where: { $0.context == currentApp.writingContext })
        let formatted = formatterPipeline.format(
            transcript: resolved,
            context: currentApp.writingContext,
            cleanupLevel: settingsStore.snapshot.cleanupLevel,
            personalization: personalizationStore.snapshot
        )

        let finalText: String
        let outcome: InsertionOutcome
        var usedFallback = false

        if activeMode == .command {
            guard let selectedText = insertionCoordinator.selectedText(), !selectedText.isEmpty else {
                failSession("Command mode requires selected text in the focused app.")
                return
            }
            let commandResult = await transformEngine.applyCommand(command: resolved, to: selectedText, context: currentApp.writingContext)
            finalText = commandResult.text
            usedFallback = commandResult.usedFallback
            outcome = insertionCoordinator.replaceSelectedText(with: finalText, in: currentApp)
            pendingSession.commandApplied = resolved
        } else {
            let cleanupResult = await transformEngine.cleanup(
                text: formatted,
                level: settingsStore.snapshot.cleanupLevel,
                context: currentApp.writingContext,
                styleProfile: style
            )
            finalText = cleanupResult.text
            usedFallback = cleanupResult.usedFallback
            outcome = insertionCoordinator.insertText(finalText, into: currentApp)
        }

        lastCommittedText = finalText
        lastInsertionOutcome = outcome
        phase = .completed
        pendingSession.finalTranscript = finalText
        pendingSession.insertionOutcome = outcome
        pendingSession.endedAt = Date()
        latestSession = pendingSession

        historyStore.add(
            HistoryEntry(
                id: UUID(),
                createdAt: Date(),
                sourceAppName: currentApp.localizedName,
                sourceAppBundleID: currentApp.bundleIdentifier,
                appContext: currentApp.writingContext,
                mode: activeMode ?? .pushToTalk,
                cleanupLevel: settingsStore.snapshot.cleanupLevel,
                finalText: finalText,
                commandApplied: pendingSession.commandApplied,
                recoveryMetadata: outcome.message,
                audioReference: settingsStore.snapshot.retainAudioHistory ? pendingSession.id.uuidString : nil,
                insertionOutcome: outcome
            )
        )

        let displayText = usedFallback
            ? finalText + "\n\n↩ Basic formatting applied — AI model unavailable"
            : finalText
        floatingBarController.update(phase: .completed, transcriptText: displayText, audioLevel: audioLevel)
        clearActiveModeAfterDelay()
    }

    private func failSession(_ message: String) {
        guard phase != .completed else { return }
        _ = audioCaptureService.stopCapture()
        transcriptionEngine.cancel()
        finalizedSessionID = pendingSession.id
        lastError = message
        phase = .failed
        lastInsertionOutcome = InsertionOutcome(succeeded: false, method: .none, message: message)
        floatingBarController.update(phase: .failed, transcriptText: message, audioLevel: audioLevel)
        clearActiveModeAfterDelay()
    }

    private func finishSessionWithoutInsertion() {
        guard finalizedSessionID != pendingSession.id else { return }
        finalizedSessionID = pendingSession.id
        finalizationFallbackTask?.cancel()
        _ = audioCaptureService.stopCapture()
        transcriptionEngine.cancel()
        phase = .idle
        activeMode = nil
        partialTranscript = ""
        audioLevel = -80
        lastError = nil
        lastInsertionOutcome = .unavailable
        floatingBarController.hide()
    }

    private func claimFinalizationForCurrentSession() -> Bool {
        guard finalizedSessionID != pendingSession.id else { return false }
        guard phase == .processing || phase == .listening else { return false }
        finalizedSessionID = pendingSession.id
        return true
    }

    private func normalizedSubstantiveTranscript(_ transcript: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: ".。!?,;: \n\t"))
            .lowercased()

        let ignoredOutputs: Set<String> = [
            "[blank_audio]",
            "blank_audio",
            "transcribing locally",
            "processing",
            "listening"
        ]

        return ignoredOutputs.contains(normalized) ? nil : trimmed
    }

    private func clearActiveModeAfterDelay() {
        let committedPhase = phase
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard let self, self.phase == committedPhase else { return }
            self.activeMode = nil
            self.audioLevel = -80
            self.floatingBarController.hide()
        }
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var selectedSidebar: SidebarDestination = .dashboard

    let permissionCenter = PermissionCenter()
    let settingsStore = SettingsStore()
    let personalizationStore = PersonalizationStore()
    let historyStore = HistoryStore()
    let notesStore = NotesStore()
    let modelManager = ModelManager()
    let runtimeInstaller = RuntimeInstaller()
    let diagnosticsExporter = DiagnosticsExporter()
    let floatingBarController = FloatingBarController()

    let sessionManager: DictationSessionManager

    private let shortcutMonitor = GlobalShortcutMonitor()
    private var started = false
    private var childObservers: Set<AnyCancellable> = []
    private var hubWindowVisible = false
    private var dockHideTask: Task<Void, Never>?

    init() {
        sessionManager = DictationSessionManager(
            audioCaptureService: LiveAudioCaptureService(),
            transcriptionEngine: AdaptiveTranscriptionEngine(modelManager: modelManager, settingsStore: settingsStore),
            transformEngine: HybridTransformEngine(modelManager: modelManager, settingsStore: settingsStore),
            formatterPipeline: FormatterPipeline(),
            insertionCoordinator: AXInsertionCoordinator(),
            contextClassifier: AppContextClassifier(),
            personalizationStore: personalizationStore,
            historyStore: historyStore,
            settingsStore: settingsStore,
            permissionCenter: permissionCenter,
            floatingBarController: floatingBarController
        )

        shortcutMonitor.onPushToTalkPressed = { [weak sessionManager] in
            sessionManager?.beginPushToTalk()
        }
        shortcutMonitor.onPushToTalkReleased = { [weak sessionManager] in
            sessionManager?.endPushToTalk()
        }
        shortcutMonitor.onHandsFreeToggle = { [weak sessionManager] in
            sessionManager?.toggleHandsFree()
        }
        shortcutMonitor.onCommandPressed = { [weak sessionManager] in
            sessionManager?.beginCommandMode()
        }
        shortcutMonitor.onCommandReleased = { [weak sessionManager] in
            sessionManager?.endCommandMode()
        }

        bridgeChildObjectChanges()

        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        permissionCenter.refresh()
        permissionCenter.startMonitoring()
        shortcutMonitor.start()

        Task {
            await settingsStore.load()
            await personalizationStore.load()
            await historyStore.load()
            await notesStore.load()
            await modelManager.load()
            permissionCenter.refresh()
            runtimeInstaller.refreshRuntimeDetections(modelManager: modelManager)
            modelManager.refreshInstalledWhisperModels()
            modelManager.refreshInstalledLlamaModels()
        }
    }

    func requestRequiredPermissions() async {
        await permissionCenter.requestMissingPermissions()
    }

    func presentHubWindow() {
        dockHideTask?.cancel()
        hubWindowVisible = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hubWindowDidClose() {
        hubWindowVisible = false
        dockHideTask?.cancel()
        dockHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, self.hubWindowVisible == false else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func installRuntime(_ kind: RuntimeInstallation.Kind) {
        runtimeInstaller.install(kind, modelManager: modelManager)
    }

    func refreshRuntimeInventory() {
        runtimeInstaller.refreshRuntimeDetections(modelManager: modelManager)
        modelManager.refreshInstalledWhisperModels()
        modelManager.refreshInstalledLlamaModels()
    }

    func installWhisperModel(_ preset: WhisperModelPreset) {
        runtimeInstaller.installWhisperModel(preset, modelManager: modelManager)
    }

    func installLlamaModel(_ preset: LlamaModelPreset) {
        runtimeInstaller.installLlamaModel(preset, modelManager: modelManager)
    }

    func cancelRuntimeInstall() {
        runtimeInstaller.cancelRuntimeInstall()
    }

    func cancelWhisperModelInstall() {
        runtimeInstaller.cancelWhisperModelInstall()
    }

    func cancelLlamaModelInstall() {
        runtimeInstaller.cancelLlamaModelInstall()
    }

    func deleteWhisperModel(_ preset: WhisperModelPreset) {
        modelManager.deleteWhisperModel(preset)
    }

    func deleteLlamaModel(_ preset: LlamaModelPreset) {
        modelManager.deleteLlamaModel(preset)
    }

    func importWhisperModel() {
        modelManager.importWhisperModelFromPanel()
    }

    func importLlamaModel() {
        modelManager.importLlamaModelFromPanel()
    }

    func exportDiagnostics(redactingContent: Bool) {
        do {
            let url = try diagnosticsExporter.export(
                permissions: permissionCenter.permissions,
                activeMode: sessionManager.activeMode,
                settings: settingsStore.snapshot,
                historyEntries: historyStore.entries,
                notes: notesStore.notes,
                runtimes: modelManager.runtimes,
                models: modelManager.descriptors,
                redactingContent: redactingContent
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            sessionManager.lastError = error.localizedDescription
        }
    }

    private func bridgeChildObjectChanges() {
        bridgeObjectChanges(from: permissionCenter)
        bridgeObjectChanges(from: settingsStore)
        bridgeObjectChanges(from: personalizationStore)
        bridgeObjectChanges(from: historyStore)
        bridgeObjectChanges(from: notesStore)
        bridgeObjectChanges(from: modelManager)
        bridgeObjectChanges(from: runtimeInstaller)
        bridgeObjectChanges(from: sessionManager)
    }

    private func bridgeObjectChanges<Object: ObservableObject>(from object: Object) where Object.ObjectWillChangePublisher == ObservableObjectPublisher {
        object.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &childObservers)
    }

}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
