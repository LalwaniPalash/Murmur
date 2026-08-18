import AppKit
import SwiftUI

/// The hub's Scratchpad page used to be a dead end whose only content was a button to
/// the real window. It now lists the notes themselves, so selecting it is never a wasted
/// click, and opening the floating window is one action among them.
struct ScratchpadLandingView: View {
    @ObservedObject var environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PanelPage(title: "Scratchpad") {
            HStack(spacing: MurmurTheme.Space.small) {
                Button("New") { open(environment.createNote()) }
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
                Button("Open") { openWindow(id: "scratchpad") }
                    .buttonStyle(PanelButtonStyle(rank: .primary))
            }
        } content: {
            PanelSection(legend: "Notes") {
                if notes.isEmpty {
                    BlankPlate(
                        legend: "No notes yet",
                        action: (title: "New note", perform: { open(environment.createNote()) })
                    )
                } else {
                    Plate(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                                if index > 0 { ScribeRule() }
                                NoteLine(note: note) { open(note.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Name the note before raising the window, so the window opens on the row that was
    /// actually clicked rather than falling back to the most recently edited note.
    private func open(_ id: UUID) {
        environment.requestedScratchpadNote = id
        openWindow(id: "scratchpad")
    }

    private var notes: [ScratchpadNote] {
        environment.notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

private struct NoteLine: View {
    let note: ScratchpadNote
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: MurmurTheme.Space.medium) {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(
                        note.isPinned ? MurmurTheme.Engraving.ink : MurmurTheme.Engraving.scribe
                    )
                    .frame(width: 12)
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(MurmurFace.body(13, weight: .medium))
                    .foregroundStyle(MurmurTheme.Engraving.ink)
                    .lineLimit(1)
                Spacer(minLength: MurmurTheme.Space.medium)
                Text(note.updatedAt, style: .relative)
                    .font(MurmurFace.readout(10))
                    .foregroundStyle(MurmurTheme.Engraving.tertiary)
            }
            .padding(.horizontal, MurmurTheme.Space.large)
            .padding(.vertical, MurmurTheme.Space.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.title.isEmpty ? "Untitled note" : note.title)
    }
}

// MARK: - Floating window

struct ScratchpadWindowView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var selectedNoteID: UUID?
    @State private var openNoteIDs: [UUID] = []
    @State private var searchText = ""
    @State private var noteForVersions: ScratchpadNote?

    var body: some View {
        HStack(spacing: 0) {
            noteColumn
                .frame(width: 208)

            Rectangle()
                .fill(MurmurTheme.Engraving.scribeStrong)
                .frame(width: MurmurTheme.Space.hairline)

            if let selectedNoteID,
               let note = environment.notes.first(where: { $0.id == selectedNoteID }) {
                VStack(spacing: 0) {
                    noteTabs
                    ScribeRule()
                    ScratchpadEditor(
                        note: note,
                        environment: environment,
                        showVersions: { noteForVersions = note },
                        delete: { delete(note) }
                    )
                }
            } else {
                VStack {
                    Legend("No note open", size: .control, color: MurmurTheme.Engraving.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MurmurTheme.Finish.panel)
            }
        }
        .background(ScratchpadWindowConfigurator())
        .onAppear { honourRequestedNote() }
        .onChange(of: environment.requestedScratchpadNote) { _, _ in honourRequestedNote() }
        .onChange(of: selectedNoteID) { _, newValue in
            if let newValue { select(newValue) }
        }
        .sheet(item: $noteForVersions) { note in
            ScratchpadVersionsView(note: note, environment: environment)
        }
    }

    private var noteColumn: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.medium) {
            HStack {
                Legend("Scratchpad", size: .section)
                Spacer()
                Button {
                    selectedNoteID = environment.createNote()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MurmurTheme.Engraving.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New note")
            }
            .padding(.horizontal, MurmurTheme.Space.medium)
            .padding(.top, MurmurTheme.Space.large)

            HStack(spacing: MurmurTheme.Space.small) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MurmurTheme.Engraving.tertiary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(MurmurFace.body(12))
                    .foregroundStyle(MurmurTheme.Engraving.ink)
                    .accessibilityLabel("Search notes")
            }
            .padding(.horizontal, MurmurTheme.Space.small)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                    .fill(MurmurTheme.Finish.recess)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                    .strokeBorder(MurmurTheme.Engraving.scribe, lineWidth: MurmurTheme.Space.hairline)
            )
            .padding(.horizontal, MurmurTheme.Space.medium)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredNotes) { note in
                        NoteColumnRow(note: note, isSelected: note.id == selectedNoteID) {
                            select(note.id)
                        }
                    }
                }
                .padding(.horizontal, MurmurTheme.Space.small)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MurmurTheme.Finish.chassis)
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
            HStack(spacing: 2) {
                ForEach(openNoteIDs, id: \.self) { noteID in
                    if let note = environment.notes.first(where: { $0.id == noteID }) {
                        // Select and close are siblings, never nested. A tap gesture on
                        // an icon inside the parent button also fires the parent, which
                        // re-selects the tab and immediately reopens what was closed.
                        HStack(spacing: MurmurTheme.Space.small) {
                            Button { selectedNoteID = noteID } label: {
                                Legend(
                                    note.title.isEmpty ? "Untitled" : note.title,
                                    size: .micro,
                                    color: selectedNoteID == noteID
                                        ? MurmurTheme.Engraving.ink
                                        : MurmurTheme.Engraving.tertiary
                                )
                                .lineLimit(1)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button { closeTab(noteID) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(MurmurTheme.Engraving.tertiary)
                                    .frame(width: 12, height: 12)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close \(note.title.isEmpty ? "Untitled" : note.title)")
                        }
                        .padding(.horizontal, MurmurTheme.Space.small)
                        .frame(height: 24)
                        .background(
                            selectedNoteID == noteID ? MurmurTheme.Finish.plate : .clear
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                        )
                    }
                }
            }
            .padding(.horizontal, MurmurTheme.Space.small)
            .padding(.vertical, MurmurTheme.Space.xSmall)
        }
        .background(MurmurTheme.Finish.chassis.opacity(0.6))
    }

    /// Consumes a note named from outside the window, falling back to the most recent
    /// note only when nothing was requested and nothing is open.
    private func honourRequestedNote() {
        if let requested = environment.requestedScratchpadNote {
            environment.requestedScratchpadNote = nil
            select(requested)
            return
        }
        guard selectedNoteID == nil, let first = filteredNotes.first else { return }
        select(first.id)
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

private struct NoteColumnRow: View {
    let note: ScratchpadNote
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MurmurTheme.Space.xSmall) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(MurmurTheme.Engraving.secondary)
                    }
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(MurmurFace.body(12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(
                            isSelected ? MurmurTheme.Engraving.ink : MurmurTheme.Engraving.secondary
                        )
                        .lineLimit(1)
                }
                Text(note.updatedAt, style: .relative)
                    .font(MurmurFace.readout(9))
                    .foregroundStyle(MurmurTheme.Engraving.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MurmurTheme.Space.small)
            .padding(.vertical, MurmurTheme.Space.small)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                        .fill(MurmurTheme.Finish.seat)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ScratchpadEditor: View {
    let note: ScratchpadNote
    @ObservedObject var environment: AppEnvironment
    let showVersions: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: MurmurTheme.Space.medium) {
                TextField(
                    "Untitled",
                    text: Binding(
                        get: { note.title },
                        set: { environment.updateNote(id: note.id, title: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(MurmurFace.legend(17, weight: .semibold))
                .foregroundStyle(MurmurTheme.Engraving.ink)
                .accessibilityLabel("Note title")

                Spacer()

                EditorAction(
                    symbol: note.isPinned ? "pin.fill" : "pin",
                    label: note.isPinned ? "Unpin note" : "Pin note"
                ) {
                    environment.updateNote(id: note.id, isPinned: !note.isPinned)
                }
                EditorAction(symbol: "clock.arrow.circlepath", label: "Version history", action: showVersions)
                EditorAction(symbol: "trash", label: "Delete note", action: delete)
            }
            .padding(.horizontal, MurmurTheme.Space.xLarge)
            .padding(.top, MurmurTheme.Space.large)
            .padding(.bottom, MurmurTheme.Space.medium)

            TextEditor(
                text: Binding(
                    get: { note.body },
                    set: { environment.updateNote(id: note.id, body: $0) }
                )
            )
            .font(MurmurFace.body(14))
            .foregroundStyle(MurmurTheme.Engraving.ink)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, MurmurTheme.Space.large)
            .padding(.bottom, MurmurTheme.Space.large)
            .accessibilityLabel("Note body")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MurmurTheme.Finish.panel)
    }
}

private struct EditorAction: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MurmurTheme.Engraving.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct ScratchpadVersionsView: View {
    let note: ScratchpadNote
    @ObservedObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
            HStack(alignment: .center) {
                Legend("Versions", size: .section)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, MurmurTheme.Space.xSmall)
            .overlay(alignment: .bottom) { ScribeRule(strong: true, ticks: true) }

            if revisions.isEmpty {
                BlankPlate(legend: "No earlier versions yet")
            } else {
                ScrollView {
                    Plate(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(revisions.enumerated()), id: \.element.id) { index, revision in
                                if index > 0 { ScribeRule() }
                                RevisionRow(revision: revision) {
                                    environment.restoreRevision(revision)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(MurmurTheme.Space.xLarge)
        .frame(width: 560, height: 440)
        .background(MurmurTheme.Finish.panel)
    }

    private var revisions: [ScratchpadRevision] {
        environment.revisions(for: note.id)
    }
}

private struct RevisionRow: View {
    let revision: ScratchpadRevision
    let restore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: MurmurTheme.Space.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(MurmurFace.readout(11))
                    .foregroundStyle(MurmurTheme.Engraving.ink)
                Text(revision.body)
                    .font(MurmurFace.body(11.5))
                    .foregroundStyle(MurmurTheme.Engraving.tertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: MurmurTheme.Space.medium)
            Button("Restore", action: restore)
                .buttonStyle(PanelButtonStyle(rank: .secondary))
        }
        .padding(.horizontal, MurmurTheme.Space.large)
        .padding(.vertical, MurmurTheme.Space.medium)
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
