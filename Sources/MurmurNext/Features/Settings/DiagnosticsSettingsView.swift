import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsSettingsView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var includePrivateContent = false
    @State private var status = ""

    var body: some View {
        PanelSection(
            legend: "Diagnostics",
            note: "The report carries system information, counts, and model names. Inspect the JSON before you send it anywhere."
        ) {
            Plate {
                VStack(alignment: .leading, spacing: MurmurTheme.Space.medium) {
                    PanelSwitch(
                        legend: "Include my writing",
                        isOn: $includePrivateContent
                    )
                    if includePrivateContent {
                        HStack(spacing: MurmurTheme.Space.small) {
                            Lamp(colour: .caution, isLit: true)
                            Text("Dictated text and notes will be written in clear text.")
                                .font(MurmurFace.body(11.5))
                                .foregroundStyle(MurmurTheme.Engraving.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ScribeRule()
                    HStack(spacing: MurmurTheme.Space.medium) {
                        Button("Export", action: export)
                            .buttonStyle(PanelButtonStyle(rank: .secondary))
                        if status.isEmpty == false {
                            Text(status)
                                .font(MurmurFace.body(11.5))
                                .foregroundStyle(MurmurTheme.Engraving.tertiary)
                        }
                    }
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
