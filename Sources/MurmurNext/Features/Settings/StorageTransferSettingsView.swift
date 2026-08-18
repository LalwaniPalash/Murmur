import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StorageTransferSettingsView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var backupPassword = ""
    @State private var pendingLibraryPreview: MurmurLibraryImportPreview?
    @State private var pendingRestoreData: Data?
    @State private var message = ""
    @State private var errorMessage = ""
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
            PanelSection(
                legend: "Library",
                note: "Terms, snippets, and styles. Never history or notes."
            ) {
                Plate {
                    HStack(spacing: MurmurTheme.Space.small) {
                        Button("Import", action: importLibrary)
                            .buttonStyle(PanelButtonStyle(rank: .secondary))
                        Button("Export", action: exportLibrary)
                            .buttonStyle(PanelButtonStyle(rank: .secondary))
                    }
                }
            }

            PanelSection(
                legend: "Backup",
                note: "History, personalization, notes, and settings. Murmur cannot recover this password."
            ) {
                Plate {
                    VStack(alignment: .leading, spacing: MurmurTheme.Space.medium) {
                        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                            Legend("Password", size: .micro, color: MurmurTheme.Engraving.tertiary)
                            SecureField("12 characters or more", text: $backupPassword)
                                .textFieldStyle(.plain)
                                .font(MurmurFace.body(13))
                                .foregroundStyle(MurmurTheme.Engraving.ink)
                                .padding(.horizontal, MurmurTheme.Space.small)
                                .padding(.vertical, MurmurTheme.Space.small)
                                .background(
                                    RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                                        .fill(
                                            MurmurTheme.Finish.recess
                                                .shadow(.inner(color: .black.opacity(0.18), radius: 2, x: 0, y: 1))
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                                        .strokeBorder(
                                            MurmurTheme.Engraving.scribe,
                                            lineWidth: MurmurTheme.Space.hairline
                                        )
                                )
                                .accessibilityLabel("Backup password")
                        }

                        HStack(spacing: MurmurTheme.Space.small) {
                            Button("Restore", action: chooseBackupToRestore)
                                .buttonStyle(PanelButtonStyle(rank: .secondary))
                            Button("Create", action: createBackup)
                                .buttonStyle(PanelButtonStyle(rank: .primary))
                            if isWorking {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .disabled(backupPassword.utf8.count < 12 || isWorking)
                    }
                }
            }

            if message.isEmpty == false {
                StatusLine(text: message, lamp: .verify)
            }
            if errorMessage.isEmpty == false {
                StatusLine(text: errorMessage, lamp: .caution)
            }
        }
        .alert("Import this library?", isPresented: libraryAlertBinding) {
            Button("Cancel", role: .cancel) { pendingLibraryPreview = nil }
            Button("Import") { applyLibraryImport() }
        } message: {
            if let preview = pendingLibraryPreview {
                Text("Add \(preview.dictionaryToImport.count) dictionary entries, \(preview.snippetsToImport.count) snippets, and \(preview.stylesToImport.count) styles. \(preview.duplicateDictionaryCount + preview.duplicateSnippetCount) duplicates will be skipped.")
            }
        }
        .alert("Replace local Murmur data?", isPresented: restoreAlertBinding) {
            Button("Cancel", role: .cancel) { pendingRestoreData = nil }
            Button("Restore", role: .destructive) { restoreBackup() }
        } message: {
            Text("This atomically replaces current history, personalization, notes, and settings with the encrypted backup. Create a current backup first if you may need to undo it.")
        }
    }

    private var libraryAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingLibraryPreview != nil },
            set: { if $0 == false { pendingLibraryPreview = nil } }
        )
    }

    private var restoreAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingRestoreData != nil },
            set: { if $0 == false { pendingRestoreData = nil } }
        )
    }

    private func exportLibrary() {
        clearStatus()
        do {
            let data = try environment.encodedLibrary()
            guard let url = saveDestination(name: "Murmur Library.murmurlibrary", type: .json) else { return }
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            message = "Library exported."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importLibrary() {
        clearStatus()
        guard let url = openSource(allowedTypes: [.json]) else { return }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let preview = try environment.previewLibraryImport(data)
            guard preview.hasChanges else {
                message = "Everything in this library is already present."
                return
            }
            pendingLibraryPreview = preview
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyLibraryImport() {
        guard let preview = pendingLibraryPreview else { return }
        environment.applyLibraryImport(preview)
        pendingLibraryPreview = nil
        message = "Library imported."
    }

    private func createBackup() {
        clearStatus()
        guard let url = saveDestination(name: "Murmur Backup.murmurbackup", type: .data) else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let data = try await environment.encryptedBackup(password: backupPassword)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                backupPassword = ""
                message = "Encrypted backup created."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseBackupToRestore() {
        clearStatus()
        guard let url = openSource(allowedTypes: [.data, .json]) else { return }
        do {
            pendingRestoreData = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreBackup() {
        guard let data = pendingRestoreData else { return }
        pendingRestoreData = nil
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await environment.restoreEncryptedBackup(data, password: backupPassword)
                backupPassword = ""
                message = "Encrypted backup restored."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearStatus() {
        message = ""
        errorMessage = ""
    }

    private func saveDestination(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func openSource(allowedTypes: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
