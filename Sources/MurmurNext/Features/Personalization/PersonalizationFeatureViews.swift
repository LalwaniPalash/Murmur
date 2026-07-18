import SwiftUI

struct DictionaryFeatureView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var isPresentingAddSheet = false

    var body: some View {
        FeatureCollectionPage(
            title: "Dictionary",
            subtitle: "Teach Murmur the names, terms, and exact spellings that matter to you.",
            searchPlaceholder: "Search dictionary",
            itemCount: environment.dictionary.count,
            addTitle: "Add word",
            emptyIcon: "character.book.closed",
            emptyTitle: "Make Murmur fluent in your words",
            emptyMessage: "Add names, products, acronyms, and technical terms so they are always written correctly.",
            isPresentingAddSheet: $isPresentingAddSheet
        ) { query in
            ForEach(filteredDictionary(query: query)) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.writtenForm).font(.system(size: 14, weight: .semibold))
                        if item.spokenForm.caseInsensitiveCompare(item.writtenForm) != .orderedSame {
                            Text("When you say “\(item.spokenForm)”")
                                .font(.system(size: 12))
                                .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                        }
                    }
                    Spacer()
                    Text(item.context?.title ?? "Everywhere")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                    Button {
                        environment.removeDictionaryItem(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                    .accessibilityLabel("Delete \(item.writtenForm)")
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
        .sheet(isPresented: $isPresentingAddSheet) {
            AddDictionaryItemSheet(environment: environment, isPresented: $isPresentingAddSheet)
        }
    }

    private func filteredDictionary(query: String) -> [DictionaryItem] {
        guard query.isEmpty == false else { return environment.dictionary }
        return environment.dictionary.filter {
            $0.spokenForm.localizedCaseInsensitiveContains(query)
                || $0.writtenForm.localizedCaseInsensitiveContains(query)
        }
    }
}

struct SnippetsFeatureView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var isPresentingAddSheet = false

    var body: some View {
        FeatureCollectionPage(
            title: "Snippets",
            subtitle: "Say a short trigger and insert the full text you use again and again.",
            searchPlaceholder: "Search snippets",
            itemCount: environment.snippets.count,
            addTitle: "Add snippet",
            emptyIcon: "text.badge.plus",
            emptyTitle: "Turn a phrase into anything",
            emptyMessage: "Save signatures, links, addresses, prompts, or full replies behind a natural voice trigger.",
            isPresentingAddSheet: $isPresentingAddSheet
        ) { query in
            ForEach(filteredSnippets(query: query)) { snippet in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(snippet.trigger).font(.system(size: 14, weight: .semibold))
                        Text(snippet.expansion)
                            .font(.system(size: 12))
                            .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        environment.removeSnippet(id: snippet.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                    .accessibilityLabel("Delete \(snippet.trigger)")
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
        .sheet(isPresented: $isPresentingAddSheet) {
            AddSnippetSheet(environment: environment, isPresented: $isPresentingAddSheet)
        }
    }

    private func filteredSnippets(query: String) -> [SnippetItem] {
        guard query.isEmpty == false else { return environment.snippets }
        return environment.snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(query)
                || $0.expansion.localizedCaseInsensitiveContains(query)
        }
    }
}

struct StyleFeatureView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
                PageHeader(title: "Style", subtitle: "Shape how Murmur writes depending on where your words are going.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                    ForEach(environment.styles) { style in
                        MurmurCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(style.name)
                                        .font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: { style.isEnabled },
                                            set: { isEnabled in
                                                environment.updateStyle(id: style.id) { $0.isEnabled = isEnabled }
                                            }
                                        )
                                    )
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                }
                                Text(style.context.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .textCase(.uppercase)
                                    .tracking(0.7)
                                    .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                                Text(style.instructions)
                                    .font(.system(size: 13))
                                    .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(MurmurTheme.Space.xLarge)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }
}

private struct FeatureCollectionPage<Rows: View>: View {
    let title: String
    let subtitle: String
    let searchPlaceholder: String
    let itemCount: Int
    let addTitle: String
    let emptyIcon: String
    let emptyTitle: String
    let emptyMessage: String
    @Binding var isPresentingAddSheet: Bool
    @ViewBuilder var rows: (String) -> Rows
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
            HStack(alignment: .bottom) {
                PageHeader(title: title, subtitle: subtitle)
                Spacer()
                Button(addTitle) { isPresentingAddSheet = true }
                    .buttonStyle(MurmurPrimaryButtonStyle())
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                TextField(searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(MurmurTheme.ColorToken.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Radius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MurmurTheme.Radius.small, style: .continuous)
                    .stroke(MurmurTheme.ColorToken.line)
            }

            MurmurCard {
                if itemCount == 0 {
                    EmptyFeatureView(
                        icon: emptyIcon,
                        title: emptyTitle,
                        message: emptyMessage,
                        actionTitle: addTitle,
                        action: { isPresentingAddSheet = true }
                    )
                } else {
                    VStack(spacing: 0) { rows(searchText) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(MurmurTheme.Space.xLarge)
        .frame(maxWidth: 920, alignment: .leading)
    }
}

private struct AddDictionaryItemSheet: View {
    @ObservedObject var environment: AppEnvironment
    @Binding var isPresented: Bool
    @State private var spokenForm = ""
    @State private var writtenForm = ""
    @State private var context: WritingContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add to dictionary").font(.system(size: 20, weight: .semibold))
            TextField("What you might say", text: $spokenForm)
            TextField("How Murmur should write it", text: $writtenForm)
            Picker("Use in", selection: $context) {
                Text("Everywhere").tag(WritingContext?.none)
                ForEach(WritingContext.allCases) { context in
                    Text(context.title).tag(Optional(context))
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(MurmurSecondaryButtonStyle())
                Button("Add word") {
                    if environment.addDictionaryItem(
                        spokenForm: spokenForm,
                        writtenForm: writtenForm.isEmpty ? spokenForm : writtenForm,
                        context: context
                    ) {
                        isPresented = false
                    }
                }
                .buttonStyle(MurmurPrimaryButtonStyle())
                .disabled(spokenForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 460)
        .background(MurmurTheme.ColorToken.canvas)
    }
}

private struct AddSnippetSheet: View {
    @ObservedObject var environment: AppEnvironment
    @Binding var isPresented: Bool
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add snippet").font(.system(size: 20, weight: .semibold))
            TextField("Voice trigger", text: $trigger)
            TextEditor(text: $expansion)
                .frame(height: 150)
                .padding(8)
                .background(MurmurTheme.ColorToken.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Radius.small))
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(MurmurSecondaryButtonStyle())
                Button("Add snippet") {
                    if environment.addSnippet(trigger: trigger, expansion: expansion) {
                        isPresented = false
                    }
                }
                .buttonStyle(MurmurPrimaryButtonStyle())
                .disabled(trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || expansion.isEmpty)
            }
        }
        .padding(26)
        .frame(width: 520)
        .background(MurmurTheme.ColorToken.canvas)
    }
}
