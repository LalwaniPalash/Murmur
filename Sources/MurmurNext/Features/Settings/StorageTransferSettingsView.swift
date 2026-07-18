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
        VStack(spacing: 12) {
            MurmurCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Personal library")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Share dictionary terms, snippets, and writing styles without including history or notes.")
                        .font(.system(size: 12))
                        .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                    HStack {
                        Button("Import library…", action: importLibrary)
                            .buttonStyle(MurmurSecondaryButtonStyle())
                        Button("Export library…", action: exportLibrary)
                            .buttonStyle(MurmurSecondaryButtonStyle())
                    }
                }
            }

            MurmurCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Encrypted backup")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Includes history, personalization, notes, and settings. The password cannot be recovered by Murmur.")
                        .font(.system(size: 12))
                        .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                    SecureField("Backup password (12+ characters)", text: $backupPassword)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Restore backup…", action: chooseBackupToRestore)
                            .buttonStyle(MurmurSecondaryButtonStyle())
                        Button("Create backup…", action: createBackup)
                            .buttonStyle(MurmurPrimaryButtonStyle())
                    }
                    .disabled(backupPassword.utf8.count < 12 || isWorking)
                    if isWorking { ProgressView().controlSize(.small) }
                }
            }

            if message.isEmpty == false {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(MurmurTheme.ColorToken.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if errorMessage.isEmpty == false {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(MurmurTheme.ColorToken.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
