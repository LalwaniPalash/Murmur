import Foundation
import Testing
@testable import MurmurNext

struct LibraryTransferServiceTests {
    @Test func libraryImportPreviewsDuplicatesBeforeApplying() throws {
        let existing = DictionaryItem(
            id: UUID(),
            spokenForm: "super base",
            writtenForm: "Supabase",
            context: .code,
            createdAt: .now
        )
        let incoming = MurmurLibraryBundle(
            dictionary: [
                DictionaryItem(
                    id: UUID(),
                    spokenForm: " Super   Base ",
                    writtenForm: "Supabase",
                    context: .code,
                    createdAt: .now
                ),
                DictionaryItem(
                    id: UUID(),
                    spokenForm: "queue bun",
                    writtenForm: "Qwen",
                    context: nil,
                    createdAt: .now
                ),
            ],
            snippets: [],
            styles: []
        )

        let data = try MurmurLibraryTransferService().encode(incoming)
        let preview = try MurmurLibraryTransferService().preview(
            data,
            existingDictionary: [existing],
            existingSnippets: []
        )

        #expect(preview.dictionaryToImport.map(\.writtenForm) == ["Qwen"])
        #expect(preview.duplicateDictionaryCount == 1)
        #expect(preview.hasChanges)
    }

    @Test func libraryImportRejectsOversizedFieldsAndUnknownVersions() throws {
        let oversized = MurmurLibraryBundle(
            dictionary: [],
            snippets: [
                SnippetItem(id: UUID(), trigger: "large", expansion: String(repeating: "x", count: 1_000_001), createdAt: .now),
            ],
            styles: []
        )
        let service = MurmurLibraryTransferService()
        #expect(throws: MurmurTransferError.self) {
            _ = try service.encode(oversized)
        }

        let unsupported = Data(#"{"format":"murmur-library","version":99,"dictionary":[],"snippets":[],"styles":[]}"#.utf8)
        #expect(throws: MurmurTransferError.self) {
            _ = try service.preview(unsupported, existingDictionary: [], existingSnippets: [])
        }
    }

    @Test func passwordBackupRoundTripsWithoutPlaintextOrKeychainKey() throws {
        let record = TranscriptRecord(
            id: UUID(),
            createdAt: .now,
            sourceApplication: "Mail",
            sourceBundleIdentifier: "com.apple.mail",
            context: .email,
            mode: .pushToTalk,
            text: "Private whispered launch plan.",
            duration: 3,
            wordsPerMinute: 80,
            insertionSucceeded: true
        )
        let payload = MurmurBackupPayload(
            exportedAt: .now,
            history: [record],
            dictionary: [],
            snippets: [],
            styles: [],
            notes: [],
            settings: .default
        )
        let service = MurmurBackupService(iterations: 1_000)
        let encrypted = try service.encrypt(payload, password: "a long unique passphrase")

        #expect(encrypted.range(of: Data(record.text.utf8)) == nil)
        let decrypted = try service.decrypt(encrypted, password: "a long unique passphrase")
        #expect(decrypted.history.map(\.id) == [record.id])
        #expect(decrypted.history.map(\.text) == [record.text])
        #expect(decrypted.settings == payload.settings)
        #expect(throws: MurmurTransferError.self) {
            _ = try service.decrypt(encrypted, password: "wrong passphrase")
        }
    }

    @Test func backupRequiresASubstantivePassword() {
        let payload = MurmurBackupPayload(
            exportedAt: .now,
            history: [],
            dictionary: [],
            snippets: [],
            styles: [],
            notes: [],
            settings: .default
        )
        #expect(throws: MurmurTransferError.self) {
            _ = try MurmurBackupService(iterations: 1_000).encrypt(payload, password: "short")
        }
    }

    @Test func backupRejectsOversizedPrivateFieldsBeforeEncryption() {
        let note = ScratchpadNote(
            id: UUID(),
            title: "Large",
            body: String(repeating: "x", count: 1_000_001),
            isPinned: false,
            createdAt: .now,
            updatedAt: .now
        )
        let payload = MurmurBackupPayload(
            exportedAt: .now,
            history: [],
            dictionary: [],
            snippets: [],
            styles: [],
            notes: [note],
            settings: .default
        )
        #expect(throws: MurmurTransferError.self) {
            _ = try MurmurBackupService(iterations: 1_000).encrypt(
                payload,
                password: "a long unique passphrase"
            )
        }
    }
}
