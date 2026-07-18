import AppKit
import SwiftUI

struct HomeFeatureView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
                PageHeader(
                    eyebrow: "Local voice writing",
                    title: "Good evening",
                    subtitle: "Speak naturally—even quietly. Murmur writes only what you meant."
                )

                UsageStrip(summary: environment.usage)

                HStack {
                    Text("Recent dictations")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MurmurTheme.ColorToken.ink)
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                        TextField("Search history", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 180)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(MurmurTheme.ColorToken.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Radius.small))
                    .overlay { RoundedRectangle(cornerRadius: MurmurTheme.Radius.small).stroke(MurmurTheme.ColorToken.line) }
                }
                .padding(.top, 4)

                if environment.history.isEmpty {
                    MurmurCard {
                        EmptyFeatureView(
                            icon: "waveform",
                            title: "Your voice history starts here",
                            message: "Hold the dictation shortcut in any text field. Your corrected text will appear here after it is inserted."
                        )
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groupedHistory, id: \.date) { group in
                            Text(group.label)
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                                .textCase(.uppercase)
                                .padding(.top, 4)
                            ForEach(group.records) { record in
                                TranscriptRow(record: record, environment: environment)
                            }
                        }
                    }
                }
            }
            .padding(MurmurTheme.Space.xLarge)
            .frame(maxWidth: 920, alignment: .leading)
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

private struct UsageStrip: View {
    let summary: UsageSummary

    var body: some View {
        HStack(spacing: 0) {
            UsageMetric(value: summary.words.formatted(), label: "Words spoken")
            Divider().frame(height: 42)
            UsageMetric(value: "\(summary.daysUsed)", label: "Days used")
            Divider().frame(height: 42)
            UsageMetric(value: String(format: "%.0f", summary.averageWordsPerMinute), label: "Words per minute")
            Divider().frame(height: 42)
            UsageMetric(value: "\(summary.sessions)", label: "Dictations")
        }
        .padding(.vertical, 19)
        .background(MurmurTheme.ColorToken.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MurmurTheme.Radius.medium, style: .continuous)
                .stroke(MurmurTheme.ColorToken.line)
        }
    }
}

private struct UsageMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(MurmurTheme.ColorToken.ink)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

private struct TranscriptRow: View {
    let record: TranscriptRecord
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        MurmurCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(record.sourceApplication)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(record.createdAt, style: .time)
                        .font(.system(size: 11))
                        .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                }
                Text(record.text)
                    .font(.system(size: 14))
                    .foregroundStyle(MurmurTheme.ColorToken.ink)
                    .textSelection(.enabled)
                HStack(spacing: 14) {
                    Label("\(Int(record.wordsPerMinute.rounded())) wpm", systemImage: "speedometer")
                    Label(record.context.title, systemImage: "app")
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") { copy() }
                        .buttonStyle(.plain)
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        environment.removeHistoryRecord(id: record.id)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
            }
        }
        .contextMenu {
            Button("Copy") { copy() }
            Button("Delete", role: .destructive) { environment.removeHistoryRecord(id: record.id) }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
    }
}
