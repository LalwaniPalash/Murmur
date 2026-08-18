import SwiftUI

/// Terms, snippets, and style were three destinations doing one job: teaching Murmur
/// how you write. They are one panel with three scribed divisions.
struct VocabularyFeatureView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var searchText = ""
    @State private var isAddingTerm = false
    @State private var isAddingSnippet = false

    var body: some View {
        PanelPage(title: "Vocabulary") {
            VocabularySearch(text: $searchText)
        } content: {
            PanelSection(legend: "Terms") {
                Button("Add") { isAddingTerm = true }
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
            } content: {
                if environment.dictionary.isEmpty {
                    BlankPlate(
                        legend: "No terms yet",
                        action: (title: "Add term", perform: { isAddingTerm = true })
                    )
                } else if terms.isEmpty {
                    BlankPlate(legend: "No match")
                } else {
                    Plate(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(terms.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { ScribeRule() }
                                TermRow(item: item, environment: environment)
                            }
                        }
                    }
                }
            }

            PanelSection(legend: "Snippets") {
                Button("Add") { isAddingSnippet = true }
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
            } content: {
                if environment.snippets.isEmpty {
                    BlankPlate(
                        legend: "No snippets yet",
                        action: (title: "Add snippet", perform: { isAddingSnippet = true })
                    )
                } else if snippets.isEmpty {
                    BlankPlate(legend: "No match")
                } else {
                    Plate(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                                if index > 0 { ScribeRule() }
                                SnippetRow(snippet: snippet, environment: environment)
                            }
                        }
                    }
                }
            }

            PanelSection(legend: "Style") {
                if environment.styles.isEmpty {
                    BlankPlate(legend: "No styles configured")
                } else {
                    Plate(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(environment.styles.enumerated()), id: \.element.id) { index, style in
                                if index > 0 { ScribeRule() }
                                StyleRow(style: style, environment: environment)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingTerm) {
            AddTermSheet(environment: environment, isPresented: $isAddingTerm)
        }
        .sheet(isPresented: $isAddingSnippet) {
            AddSnippetSheet(environment: environment, isPresented: $isAddingSnippet)
        }
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var terms: [DictionaryItem] {
        guard query.isEmpty == false else { return environment.dictionary }
        return environment.dictionary.filter {
            $0.spokenForm.localizedCaseInsensitiveContains(query)
                || $0.writtenForm.localizedCaseInsensitiveContains(query)
        }
    }

    private var snippets: [SnippetItem] {
        guard query.isEmpty == false else { return environment.snippets }
        return environment.snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(query)
                || $0.expansion.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Rows

private struct TermRow: View {
    let item: DictionaryItem
    @ObservedObject var environment: AppEnvironment
    @State private var isHovering = false

    private var hasDistinctSpokenForm: Bool {
        item.spokenForm.caseInsensitiveCompare(item.writtenForm) != .orderedSame
    }

    var body: some View {
        HStack(spacing: MurmurTheme.Space.medium) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.writtenForm)
                    .font(MurmurFace.body(13, weight: .medium))
                    .foregroundStyle(MurmurTheme.Engraving.ink)
                if hasDistinctSpokenForm {
                    Text("spoken “\(item.spokenForm)”")
                        .font(MurmurFace.body(11.5))
                        .foregroundStyle(MurmurTheme.Engraving.tertiary)
                }
            }
            Spacer(minLength: MurmurTheme.Space.medium)
            Legend(
                item.context?.title ?? "Everywhere",
                size: .micro,
                color: MurmurTheme.Engraving.tertiary
            )
            DeleteAction(label: "Delete \(item.writtenForm)", isVisible: isHovering) {
                environment.removeDictionaryItem(id: item.id)
            }
        }
        .padding(.horizontal, MurmurTheme.Space.large)
        .padding(.vertical, MurmurTheme.Space.medium)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct SnippetRow: View {
    let snippet: SnippetItem
    @ObservedObject var environment: AppEnvironment
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: MurmurTheme.Space.medium) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snippet.trigger)
                    .font(MurmurFace.body(13, weight: .medium))
                    .foregroundStyle(MurmurTheme.Engraving.ink)
                Text(snippet.expansion)
                    .font(MurmurFace.body(11.5))
                    .foregroundStyle(MurmurTheme.Engraving.tertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: MurmurTheme.Space.medium)
            DeleteAction(label: "Delete \(snippet.trigger)", isVisible: isHovering) {
                environment.removeSnippet(id: snippet.id)
            }
        }
        .padding(.horizontal, MurmurTheme.Space.large)
        .padding(.vertical, MurmurTheme.Space.medium)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct StyleRow: View {
    let style: WritingStyle
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        HStack(alignment: .top, spacing: MurmurTheme.Space.large) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: MurmurTheme.Space.small) {
                    Text(style.name)
                        .font(MurmurFace.body(13, weight: .medium))
                        .foregroundStyle(MurmurTheme.Engraving.ink)
                    Legend(style.context.title, size: .micro, color: MurmurTheme.Engraving.tertiary)
                }
                Text(style.instructions)
                    .font(MurmurFace.body(11.5))
                    .foregroundStyle(MurmurTheme.Engraving.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { style.isEnabled },
                set: { isEnabled in
                    environment.updateStyle(id: style.id) { $0.isEnabled = isEnabled }
                }
            ))
            .labelsHidden()
            .toggleStyle(PanelToggleStyle())
            .accessibilityLabel(style.name)
        }
        .padding(.horizontal, MurmurTheme.Space.large)
        .padding(.vertical, MurmurTheme.Space.medium)
    }
}

private struct DeleteAction: View {
    let label: String
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MurmurTheme.Engraving.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        // Opacity alone leaves the button hit-testable, which would put an invisible
        // delete target on every row.
        .allowsHitTesting(isVisible)
        .accessibilityLabel(label)
    }
}

// MARK: - Search

private struct VocabularySearch: View {
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
                .accessibilityLabel("Search terms and snippets")
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

// MARK: - Sheets

private struct SheetFrame<Content: View>: View {
    let legend: String
    let width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
            VStack(alignment: .leading, spacing: MurmurTheme.Space.xSmall) {
                Legend(legend, size: .section)
                ScribeRule(strong: true, ticks: true)
            }
            content
        }
        .padding(MurmurTheme.Space.xLarge)
        .frame(width: width)
        .background(MurmurTheme.Finish.panel)
    }
}

private struct AddTermSheet: View {
    @ObservedObject var environment: AppEnvironment
    @Binding var isPresented: Bool
    @State private var spokenForm = ""
    @State private var writtenForm = ""
    @State private var context: WritingContext?

    private var canAdd: Bool {
        spokenForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        SheetFrame(legend: "Add term", width: 440) {
            PanelField(legend: "Spoken", text: $spokenForm, prompt: "What you say")
            PanelField(legend: "Written", text: $writtenForm, prompt: "How Murmur writes it")

            VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                Legend("Applies to", size: .micro, color: MurmurTheme.Engraving.tertiary)
                Picker("", selection: $context) {
                    Text("Everywhere").tag(WritingContext?.none)
                    ForEach(WritingContext.allCases) { value in
                        Text(value.title).tag(Optional(value))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .accessibilityLabel("Applies to")
            }

            HStack(spacing: MurmurTheme.Space.small) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if environment.addDictionaryItem(
                        spokenForm: spokenForm,
                        writtenForm: writtenForm.isEmpty ? spokenForm : writtenForm,
                        context: context
                    ) {
                        isPresented = false
                    }
                }
                .buttonStyle(PanelButtonStyle(rank: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(canAdd == false)
            }
        }
    }
}

private struct AddSnippetSheet: View {
    @ObservedObject var environment: AppEnvironment
    @Binding var isPresented: Bool
    @State private var trigger = ""
    @State private var expansion = ""

    private var canAdd: Bool {
        trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && expansion.isEmpty == false
    }

    var body: some View {
        SheetFrame(legend: "Add snippet", width: 500) {
            PanelField(legend: "Trigger", text: $trigger, prompt: "What you say")
            PanelField(
                legend: "Expansion",
                text: $expansion,
                prompt: "What gets written",
                axis: .vertical,
                lineLimit: 5...9
            )

            HStack(spacing: MurmurTheme.Space.small) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if environment.addSnippet(trigger: trigger, expansion: expansion) {
                        isPresented = false
                    }
                }
                .buttonStyle(PanelButtonStyle(rank: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(canAdd == false)
            }
        }
    }
}
