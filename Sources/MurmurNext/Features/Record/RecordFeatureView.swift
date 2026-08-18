import AppKit
import MurmurQualityCore
import SwiftUI

/// The verbatim record. Entries are rows scribed into one ledger plate per day rather
/// than a card each — a dictation log is a continuous record, not a feed.
struct RecordFeatureView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var searchText = ""
    @State private var presentedSheet: RecordSheet?
    @State private var recoveryPendingDeletion: RecoveryItem?
    @State private var historyPendingDeletion: TranscriptRecord?

    var body: some View {
        PanelPage(title: "Record") {
            SearchWell(text: $searchText)
        } content: {
            if environment.isLoaded, environment.isCaptureOwner == false {
                BlankPlate(legend: "Another Murmur instance owns microphone capture and global shortcuts")
            }

            if environment.recoveryItems.isEmpty == false {
                PanelSection(legend: "Recovery") {
                    RecoveryLedger(
                        items: environment.recoveryItems,
                        environment: environment,
                        deleteAction: { recoveryPendingDeletion = $0 }
                    )
                }
            }

            if environment.history.isEmpty {
                BlankPlate(legend: "No dictations yet — hold fn in any text field")
            } else if groupedHistory.isEmpty {
                BlankPlate(legend: "No match for “\(searchText)”")
            } else {
                VStack(alignment: .leading, spacing: MurmurTheme.Space.xLarge) {
                    ForEach(groupedHistory, id: \.date) { group in
                        PanelSection(legend: group.label) {
                            Ledger(
                                records: group.records,
                                environment: environment,
                                versionsAction: { presentedSheet = .versions($0) },
                                reportAction: { presentedSheet = .report($0) },
                                deleteAction: { historyPendingDeletion = $0 }
                            )
                        }
                    }
                }
            }

            UsageStrip(summary: environment.usage)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .versions(let sessionID):
                ResultVersionsView(sessionID: sessionID, environment: environment)
            case .report(let sessionID):
                IssueBundleExportView(sessionID: sessionID, environment: environment)
            }
        }
        .alert(
            "Delete recoverable recording?",
            isPresented: Binding(
                get: { recoveryPendingDeletion != nil },
                set: { if $0 == false { recoveryPendingDeletion = nil } }
            ),
            presenting: recoveryPendingDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                environment.deleteRecovery(sessionID: item.id)
                recoveryPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { recoveryPendingDeletion = nil }
        } message: { _ in
            Text("This permanently removes the encrypted audio and any saved result versions.")
        }
        .alert(
            "Delete this dictation?",
            isPresented: Binding(
                get: { historyPendingDeletion != nil },
                set: { if $0 == false { historyPendingDeletion = nil } }
            ),
            presenting: historyPendingDeletion
        ) { record in
            Button("Delete", role: .destructive) {
                environment.removeHistoryRecord(id: record.id)
                historyPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { historyPendingDeletion = nil }
        } message: { record in
            Text(environment.retainedAudioSessionIDs.contains(record.id)
                ? "This permanently removes every transcript version and its encrypted recording."
                : "This permanently removes every transcript version.")
        }
    }

    private var filteredHistory: [TranscriptRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return environment.history }
        return environment.history.filter {
            $0.text.localizedCaseInsensitiveContains(query)
                || $0.sourceApplication.localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedHistory: [(date: Date, label: String, records: [TranscriptRecord])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredHistory) { calendar.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { date in
            let label: String
            if calendar.isDateInToday(date) {
                label = "Today"
            } else if calendar.isDateInYesterday(date) {
                label = "Yesterday"
            } else {
                label = date.formatted(date: .abbreviated, time: .omitted)
            }
            return (date, label, groups[date, default: []].sorted { $0.createdAt > $1.createdAt })
        }
    }
}

private enum RecordSheet: Identifiable {
    case versions(UUID)
    case report(UUID)

    var id: String {
        switch self {
        case .versions(let id): "versions-\(id)"
        case .report(let id): "report-\(id)"
        }
    }
}

private struct RecoveryLedger: View {
    let items: [RecoveryItem]
    @ObservedObject var environment: AppEnvironment
    let deleteAction: (RecoveryItem) -> Void

    var body: some View {
        Plate(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { ScribeRule() }
                    HStack(alignment: .firstTextBaseline, spacing: MurmurTheme.Space.medium) {
                        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                            Legend(
                                item.journal.targetApplication,
                                size: .micro,
                                color: MurmurTheme.Engraving.secondary
                            )
                            Text(recoveryDescription(item))
                                .font(MurmurFace.body(13))
                                .foregroundStyle(MurmurTheme.Engraving.ink)
                        }
                        Spacer(minLength: MurmurTheme.Space.medium)
                        recoveryActions(item)
                    }
                    .padding(.horizontal, MurmurTheme.Space.large)
                    .padding(.vertical, MurmurTheme.Space.medium)
                }
            }
        }
    }

    @ViewBuilder
    private func recoveryActions(_ item: RecoveryItem) -> some View {
        HStack(spacing: MurmurTheme.Space.small) {
            if item.actions.contains(.retryTranscription) {
                Menu("Retry") {
                    ForEach(environment.verifiedWhisperModelIdentifiers.sorted(), id: \.self) { model in
                        Button(model) {
                            Task { await environment.retryRecovery(sessionID: item.id, modelIdentifier: model) }
                        }
                    }
                }
                .disabled(environment.verifiedWhisperModelIdentifiers.isEmpty)
            }
            if item.actions.contains(.retain) {
                Button("Keep") { environment.retainRecovery(sessionID: item.id) }
            }
            if item.actions.contains(.copyText) {
                Button("Copy") { environment.copyRecoveryText(sessionID: item.id) }
            }
            if item.actions.contains(.delete) {
                Button("Delete", role: .destructive) { deleteAction(item) }
            }
        }
        .font(MurmurFace.body(11))
        .buttonStyle(.borderless)
    }

    private func recoveryDescription(_ item: RecoveryItem) -> String {
        switch item.journal.phase {
        case .capturing: "Recording was interrupted during capture."
        case .finalizing: "Recording stopped before transcription completed."
        case .inserting: "Text could not be inserted automatically."
        case .cleaningUp: "Cleanup will resume automatically."
        }
    }
}

// MARK: - Ledger

private struct Ledger: View {
    let records: [TranscriptRecord]
    @ObservedObject var environment: AppEnvironment
    let versionsAction: (UUID) -> Void
    let reportAction: (UUID) -> Void
    let deleteAction: (TranscriptRecord) -> Void

    var body: some View {
        Plate(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        ScribeRule()
                    }
                    LedgerRow(
                        record: record,
                        // A ledger names the source once and then rules under it. Repeating
                        // "Terminal" on forty consecutive rows is noise, not information.
                        showsSource: index == 0
                            || records[index - 1].sourceApplication != record.sourceApplication,
                        environment: environment,
                        versionsAction: versionsAction,
                        reportAction: reportAction,
                        deleteAction: deleteAction
                    )
                }
            }
        }
    }
}

private struct LedgerRow: View {
    let record: TranscriptRecord
    let showsSource: Bool
    @ObservedObject var environment: AppEnvironment
    let versionsAction: (UUID) -> Void
    let reportAction: (UUID) -> Void
    let deleteAction: (TranscriptRecord) -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
            // The source is named once per run of rows, so it heads its own line only
            // when it actually changes.
            if showsSource {
                Legend(
                    record.sourceApplication,
                    size: .micro,
                    color: MurmurTheme.Engraving.secondary
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: MurmurTheme.Space.medium) {
                Text(record.text)
                    .font(MurmurFace.body(13))
                    .foregroundStyle(MurmurTheme.Engraving.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: MurmurTheme.Space.medium)

                // The action cluster always occupies its width so revealing it on hover
                // cannot reflow the transcript beside it.
                HStack(spacing: 0) {
                    RowAction(symbol: "doc.on.doc", label: "Copy", action: copy)
                    RowAction(symbol: "trash", label: "Delete") {
                        deleteAction(record)
                    }
                }
                .opacity(isHovering ? 1 : 0)
                // Opacity alone leaves the button hit-testable, which would put an
                // invisible delete target on every row.
                .allowsHitTesting(isHovering)
                .frame(width: 36)

                Text(record.createdAt, style: .time)
                    .font(MurmurFace.readout(10))
                    .monospacedDigit()
                    .foregroundStyle(MurmurTheme.Engraving.tertiary)
                    .frame(width: 62, alignment: .trailing)
            }
        }
        .padding(.horizontal, MurmurTheme.Space.large)
        .padding(.vertical, MurmurTheme.Space.medium)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Copy", action: copy)
            if environment.retainedAudioSessionIDs.contains(record.id) {
                Button("Play recording") {
                    Task { await environment.playRetainedAudio(sessionID: record.id) }
                }
                Menu("Retranscribe with") {
                    ForEach(environment.verifiedWhisperModelIdentifiers.sorted(), id: \.self) { model in
                        Button(model) {
                            Task { await environment.retranscribe(sessionID: record.id, modelIdentifier: model) }
                        }
                    }
                }
            }
            Button("Versions and comparison") { versionsAction(record.id) }
            Button("Export issue bundle…") { reportAction(record.id) }
            Divider()
            Button("Delete", role: .destructive) { deleteAction(record) }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
    }
}

private struct ResultVersionsView: View {
    let sessionID: UUID
    @ObservedObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var baselineID: UUID?
    @State private var candidateID: UUID?

    init(sessionID: UUID, environment: AppEnvironment) {
        self.sessionID = sessionID
        self.environment = environment
        let versions = environment.versions(for: sessionID)
        _candidateID = State(initialValue: versions.first?.id)
        _baselineID = State(initialValue: versions.dropFirst().first?.id ?? versions.first?.id)
    }

    private var versions: [TranscriptResultVersion] { environment.versions(for: sessionID) }
    private var comparison: ResultVersionComparison? {
        guard let baselineID, let candidateID else { return nil }
        return try? environment.compareResults(
            baselineID: baselineID,
            candidateID: candidateID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
            HStack {
                Text("Result versions").font(MurmurFace.legend(22))
                Spacer()
                Button("Done") { dismiss() }
            }

            if environment.retainedAudioSessionIDs.contains(sessionID) {
                HStack {
                    Button("Play recording") {
                        Task { await environment.playRetainedAudio(sessionID: sessionID) }
                    }
                    Menu("Retranscribe with") {
                        ForEach(environment.verifiedWhisperModelIdentifiers.sorted(), id: \.self) { model in
                            Button(model) {
                                Task { await environment.retranscribe(sessionID: sessionID, modelIdentifier: model) }
                            }
                        }
                    }
                    .disabled(environment.verifiedWhisperModelIdentifiers.isEmpty)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
                    ForEach(versions) { version in
                        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                            HStack {
                                Text("\(version.providerIdentifier) · \(version.modelIdentifier) · \(version.language)")
                                    .font(MurmurFace.readout(11))
                                Spacer()
                                Text(String(format: "%.2fs", version.totalProcessingDuration))
                                    .font(MurmurFace.readout(10))
                                if environment.preferredResultID(for: sessionID) == version.id {
                                    Text("Preferred").font(MurmurFace.readout(10))
                                } else {
                                    Button("Use") {
                                        Task { await environment.selectPreferredResult(
                                            sessionID: sessionID,
                                            resultID: version.id
                                        ) }
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            Text(version.finalTranscript)
                                .font(MurmurFace.body(13))
                                .textSelection(.enabled)
                        }
                        .padding(MurmurTheme.Space.medium)
                        .background(MurmurTheme.Finish.recess)
                    }

                    if versions.count > 1 {
                        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                            Text("Comparison").font(MurmurFace.legend(16))
                            HStack {
                                Picker("Baseline", selection: $baselineID) {
                                    ForEach(versions) { version in
                                        Text(versionLabel(version)).tag(Optional(version.id))
                                    }
                                }
                                Picker("Candidate", selection: $candidateID) {
                                    ForEach(versions) { version in
                                        Text(versionLabel(version)).tag(Optional(version.id))
                                    }
                                }
                            }
                            if let comparison {
                                Text("Word difference: \(comparison.alignment.wordErrorRate.formatted(.percent.precision(.fractionLength(1))))")
                                    .font(MurmurFace.readout(11))
                                ForEach(Array(comparison.alignment.operations.enumerated()), id: \.offset) { _, edit in
                                    if edit.kind != .match {
                                        Text(editDescription(edit))
                                            .font(MurmurFace.body(12))
                                            .foregroundStyle(MurmurTheme.Engraving.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(MurmurTheme.Space.xLarge)
        .frame(minWidth: 620, minHeight: 520)
        .onDisappear { environment.stopRetainedAudio() }
    }

    private func editDescription(_ edit: TranscriptEdit) -> String {
        switch edit.kind {
        case .match: ""
        case .substitution: "Changed “\(edit.expected?.original ?? "")” → “\(edit.actual?.original ?? "")”"
        case .insertion: "Added “\(edit.actual?.original ?? "")”"
        case .deletion: "Removed “\(edit.expected?.original ?? "")”"
        }
    }

    private func versionLabel(_ version: TranscriptResultVersion) -> String {
        "\(version.modelIdentifier) · \(version.createdAt.formatted(date: .omitted, time: .shortened))"
    }
}

private struct IssueBundleExportView: View {
    let sessionID: UUID
    @ObservedObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var includeTranscript = false
    @State private var includeAudio = false
    @State private var preview: IssueBundlePreview?
    @State private var errorMessage: String?

    private var options: IssueBundleOptions {
        IssueBundleOptions(includeTranscript: includeTranscript, includeAudio: includeAudio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
            HStack {
                Text("Issue bundle").font(MurmurFace.legend(22))
                Spacer()
                Button("Cancel") { dismiss() }
            }
            Text("Environment and timing metadata are included. Private content stays off unless you select it.")
                .font(MurmurFace.body(13))
                .foregroundStyle(MurmurTheme.Engraving.secondary)
            Toggle("Include transcript", isOn: $includeTranscript)
            Toggle("Include retained audio", isOn: $includeAudio)
                .disabled(environment.retainedAudioSessionIDs.contains(sessionID) == false)

            if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                        ForEach(preview.fields) { field in
                            HStack {
                                Image(systemName: field.isIncluded ? "checkmark.circle.fill" : "circle")
                                Text(field.path).font(MurmurFace.readout(11))
                                if field.isPrivate { Text("Private").font(MurmurFace.readout(9)) }
                            }
                            .foregroundStyle(field.isIncluded
                                ? MurmurTheme.Engraving.ink
                                : MurmurTheme.Engraving.tertiary)
                        }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(MurmurFace.body(12))
            }
            HStack {
                Spacer()
                Button("Export…", action: export)
            }
        }
        .padding(MurmurTheme.Space.xLarge)
        .frame(width: 560, height: 520)
        .task(id: "\(includeTranscript)-\(includeAudio)") { await refreshPreview() }
    }

    private func refreshPreview() async {
        do {
            preview = try await environment.issueBundlePreview(sessionID: sessionID, options: options)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func export() {
        Task {
            do {
                let data = try await environment.issueBundle(sessionID: sessionID, options: options)
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = "murmur-issue-\(sessionID.uuidString.lowercased()).json"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct RowAction: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MurmurTheme.Engraving.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Search

private struct SearchWell: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: MurmurTheme.Space.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MurmurTheme.Engraving.tertiary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(MurmurFace.body(12))
                .foregroundStyle(MurmurTheme.Engraving.ink)
                .frame(width: 150)
                .accessibilityLabel("Search the record")
        }
        .padding(.horizontal, MurmurTheme.Space.small)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                .fill(
                    MurmurTheme.Finish.recess
                        .shadow(.inner(color: .black.opacity(0.18), radius: 2, x: 0, y: 1))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                .strokeBorder(MurmurTheme.Engraving.scribe, lineWidth: MurmurTheme.Space.hairline)
        )
    }
}

// MARK: - Usage

/// Demoted from a hero metric row to what it is: a totals strip scribed at the foot of
/// the panel, in tabular figures, below the content it describes.
private struct UsageStrip: View {
    let summary: UsageSummary

    var body: some View {
        VStack(spacing: MurmurTheme.Space.medium) {
            ScribeRule(ticks: true)
            HStack(alignment: .top, spacing: MurmurTheme.Space.xxLarge) {
                Readout(legend: "Words", value: summary.words.formatted())
                Readout(legend: "Dictations", value: "\(summary.sessions)")
                Readout(
                    legend: "Rate",
                    value: String(format: "%.0f", summary.averageWordsPerMinute),
                    unit: "wpm"
                )
                Readout(legend: "Days", value: "\(summary.daysUsed)")
                Spacer(minLength: 0)
            }
        }
        .padding(.top, MurmurTheme.Space.large)
    }
}
