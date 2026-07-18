import AppKit
import SwiftUI

struct ScratchpadLandingView: View {
    @ObservedObject var environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
                HStack(alignment: .bottom) {
                    PageHeader(title: "Scratchpad", subtitle: "A quiet place for thoughts that are not ready for another app yet.")
                    Spacer()
                    Button("Open Scratchpad") { openWindow(id: "scratchpad") }
                        .buttonStyle(MurmurPrimaryButtonStyle())
                }
                MurmurCard {
                    EmptyFeatureView(
                        icon: "square.and.pencil",
                        title: "Keep a thought within reach",
                        message: "Scratchpad floats above your work and saves every edit locally.",
                        actionTitle: "Create a note"
                    ) {
                        _ = environment.createNote()
                        openWindow(id: "scratchpad")
                    }
                }
            }
            .padding(MurmurTheme.Space.xLarge)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }
}

struct ScratchpadWindowView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var selectedNoteID: UUID?
    @State private var openNoteIDs: [UUID] = []
    @State private var searchText = ""
    @State private var noteForVersions: ScratchpadNote?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Scratchpad")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Button {
                        selectedNoteID = environment.createNote()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                    TextField("Search notes", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(MurmurTheme.ColorToken.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)

                List(selection: $selectedNoteID) {
                    ForEach(filteredNotes.map(\.id), id: \.self) { noteID in
                        ScratchpadNoteLookup(noteID: noteID, notes: filteredNotes)
                            .tag(noteID)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .frame(width: 220)
            .background(MurmurTheme.ColorToken.sidebar)

            Divider()

            if let selectedNoteID,
               let note = environment.notes.first(where: { $0.id == selectedNoteID }) {
                VStack(spacing: 0) {
                    noteTabs
                    Divider()
                    ScratchpadEditor(
                        note: note,
                        environment: environment,
                        showVersions: { noteForVersions = note },
                        delete: { delete(note) }
                    )
                }
            } else {
                EmptyFeatureView(
                    icon: "note.text",
                    title: "No note selected",
                    message: "Create a note to start writing."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MurmurTheme.ColorToken.canvas)
            }
        }
        .preferredColorScheme(.light)
        .background(ScratchpadWindowConfigurator())
        .onAppear {
            guard selectedNoteID == nil, let first = filteredNotes.first else { return }
            select(first.id)
        }
        .onChange(of: selectedNoteID) { _, newValue in
            if let newValue { select(newValue) }
        }
        .sheet(item: $noteForVersions) { note in
            ScratchpadVersionsView(note: note, environment: environment)
        }
    }

    private var filteredNotes: [ScratchpadNote] {
        environment.notes
            .filter { note in
                searchText.isEmpty
                    || note.title.localizedCaseInsensitiveContains(searchText)
                    || note.body.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private var noteTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(openNoteIDs, id: \.self) { noteID in
                    if let note = environment.notes.first(where: { $0.id == noteID }) {
                        Button {
                            selectedNoteID = noteID
                        } label: {
                            HStack(spacing: 7) {
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .onTapGesture { closeTab(noteID) }
                            }
                            .font(.system(size: 11, weight: selectedNoteID == noteID ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(selectedNoteID == noteID ? MurmurTheme.ColorToken.surfaceRaised : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(MurmurTheme.ColorToken.sidebar.opacity(0.55))
    }

    private func select(_ id: UUID) {
        selectedNoteID = id
        if openNoteIDs.contains(id) == false { openNoteIDs.append(id) }
    }

    private func closeTab(_ id: UUID) {
        openNoteIDs.removeAll { $0 == id }
        if selectedNoteID == id { selectedNoteID = openNoteIDs.last ?? filteredNotes.first?.id }
    }

    private func delete(_ note: ScratchpadNote) {
        closeTab(note.id)
        environment.deleteNote(id: note.id)
    }
}

private struct ScratchpadNoteLookup: View {
    let noteID: UUID
    let notes: [ScratchpadNote]

    @ViewBuilder var body: some View {
        if let note = notes.first(where: { $0.id == noteID }) {
            ScratchpadNoteRow(note: note)
        }
    }
}

private struct ScratchpadNoteRow: View {
    let note: ScratchpadNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(MurmurTheme.ColorToken.warning)
                }
                Text(note.title.isEmpty ? "Untitled note" : note.title).lineLimit(1)
            }
            Text(note.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
        }
    }
}

private struct ScratchpadEditor: View {
    let note: ScratchpadNote
    @ObservedObject var environment: AppEnvironment
    let showVersions: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                TextField(
                    "Note title",
                    text: Binding(
                        get: { note.title },
                        set: { environment.updateNote(id: note.id, title: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    environment.updateNote(id: note.id, isPinned: !note.isPinned)
                } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .help(note.isPinned ? "Unpin note" : "Pin note")
                Button(action: showVersions) { Image(systemName: "clock.arrow.circlepath") }
                    .buttonStyle(.plain)
                    .help("Version history")
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .help("Delete note")
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 12)

            TextEditor(
                text: Binding(
                    get: { note.body },
                    set: { environment.updateNote(id: note.id, body: $0) }
                )
            )
            .font(.system(size: 15))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MurmurTheme.ColorToken.canvas)
    }
}

private struct ScratchpadVersionsView: View {
    let note: ScratchpadNote
    @ObservedObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version history").font(.system(size: 20, weight: .semibold))
                    Text(note.title.isEmpty ? "Untitled note" : note.title)
                        .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(MurmurSecondaryButtonStyle())
            }
            if revisions.isEmpty {
                EmptyFeatureView(
                    icon: "clock.arrow.circlepath",
                    title: "No earlier versions yet",
                    message: "Murmur creates local snapshots as this note changes."
                )
            } else {
                List(revisions) { revision in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 13, weight: .semibold))
                            Text(revision.body)
                                .font(.system(size: 12))
                                .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("Restore") {
                            environment.restoreRevision(revision)
                            dismiss()
                        }
                        .buttonStyle(MurmurSecondaryButtonStyle())
                    }
                    .padding(.vertical, 5)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(24)
        .frame(width: 560, height: 440)
        .background(MurmurTheme.ColorToken.canvas)
    }

    private var revisions: [ScratchpadRevision] {
        environment.revisions(for: note.id)
    }
}

private struct ScratchpadWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        window?.level = .floating
        window?.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        window?.isReleasedWhenClosed = false
    }
}
