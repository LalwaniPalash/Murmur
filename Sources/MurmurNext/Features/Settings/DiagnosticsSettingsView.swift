import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsSettingsView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var includePrivateContent = false
    @State private var status = ""

    var body: some View {
        MurmurCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Diagnostics export")
                    .font(.system(size: 14, weight: .semibold))
                Text("The default report includes only system information, counts, and installed model names. You can inspect the JSON before sharing it.")
                    .font(.system(size: 12))
                    .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                Toggle("Include dictated and note content", isOn: $includePrivateContent)
                    .font(.system(size: 12, weight: .medium))
                if includePrivateContent {
                    Label("Private writing will be included in clear text.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MurmurTheme.ColorToken.warning)
                }
                Button("Export diagnostics…", action: export)
                    .buttonStyle(MurmurSecondaryButtonStyle())
                if status.isEmpty == false {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                }
            }
        }
    }

    private func export() {
        do {
            let data = try DiagnosticsExportService().makeReport(
                history: environment.history,
                notes: environment.notes,
                modelIdentifiers: Array(environment.verifiedWhisperModelIdentifiers),
                includeContent: includePrivateContent
            )
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Murmur Diagnostics.json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            status = includePrivateContent
                ? "Content-inclusive diagnostics exported."
                : "Redacted diagnostics exported."
        } catch {
            status = error.localizedDescription
        }
    }
}
