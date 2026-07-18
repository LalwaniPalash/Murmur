import Foundation
import Testing
@testable import MurmurNext

struct ScratchpadRevisionPolicyTests {
    @Test func createsFirstMeaningfulRevisionAndRateLimitsSmallEdits() {
        let note = ScratchpadNote(
            id: UUID(),
            title: "Idea",
            body: "A meaningful first thought",
            isPinned: false,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let policy = ScratchpadRevisionPolicy(minimumInterval: 30, minimumCharacterDelta: 80)
        #expect(policy.shouldCreateRevision(previous: nil, note: note, now: note.updatedAt))

        let previous = ScratchpadRevision(
            id: UUID(),
            noteID: note.id,
            title: note.title,
            body: note.body,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        var smallEdit = note
        smallEdit.body += "."
        #expect(policy.shouldCreateRevision(
            previous: previous,
            note: smallEdit,
            now: Date(timeIntervalSince1970: 20)
        ) == false)
    }

    @Test func snapshotsAfterTimeOrMaterialChange() {
        let noteID = UUID()
        let previous = ScratchpadRevision(
            id: UUID(),
            noteID: noteID,
            title: "Draft",
            body: "Short",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let policy = ScratchpadRevisionPolicy(minimumInterval: 30, minimumCharacterDelta: 20)
        let timed = ScratchpadNote(
            id: noteID,
            title: "Draft",
            body: "Short edit",
            isPinned: false,
            createdAt: .distantPast,
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        var material = timed
        material.updatedAt = Date(timeIntervalSince1970: 12)
        material.body = String(repeating: "x", count: 40)

        #expect(policy.shouldCreateRevision(previous: previous, note: timed, now: timed.updatedAt))
        #expect(policy.shouldCreateRevision(previous: previous, note: material, now: material.updatedAt))
    }
}
