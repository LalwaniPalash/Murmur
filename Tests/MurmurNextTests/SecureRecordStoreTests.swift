import CryptoKit
import Foundation
import Testing
@testable import MurmurNext

struct SecureRecordStoreTests {
    @Test func encryptedCodecRoundTripsAndRejectsTampering() throws {
        let key = SymmetricKey(data: Data(repeating: 0x2A, count: 32))
        let codec = EncryptedPayloadCodec(key: key)
        let original = SnippetItem(
            id: UUID(),
            trigger: "meeting link",
            expansion: "https://example.com/private",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let encrypted = try codec.encrypt(original)
        #expect(String(data: encrypted, encoding: .utf8) == nil)
        let decoded: SnippetItem = try codec.decrypt(encrypted)
        #expect(decoded == original)

        var tampered = encrypted
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        #expect(throws: (any Error).self) {
            let _: SnippetItem = try codec.decrypt(tampered)
        }
    }

    @Test func storesAndSearchesEncryptedRecordsUsingBlindTerms() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let first = TranscriptRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 300),
            sourceApplication: "Mail",
            sourceBundleIdentifier: "com.apple.mail",
            context: .email,
            mode: .pushToTalk,
            text: "Whisper the private launch notes.",
            duration: 4,
            wordsPerMinute: 75,
            insertionSucceeded: true
        )
        let second = TranscriptRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 200),
            sourceApplication: "Messages",
            sourceBundleIdentifier: "com.apple.MobileSMS",
            context: .messaging,
            mode: .pushToTalk,
            text: "Dinner will be ready soon.",
            duration: 3,
            wordsPerMinute: 100,
            insertionSucceeded: true
        )

        try await store.save(first, collection: .history, searchableText: first.text)
        try await store.save(second, collection: .history, searchableText: second.text)

        let all: [TranscriptRecord] = try await store.fetch(collection: .history)
        let matches: [TranscriptRecord] = try await store.fetch(collection: .history, matching: "private whisper")
        #expect(all.map(\.id) == [first.id, second.id])
        #expect(matches.map(\.id) == [first.id])

        let rawDatabase = try Data(contentsOf: fixture.databaseURL)
        #expect(rawDatabase.range(of: Data("private launch notes".utf8)) == nil)
        #expect(rawDatabase.range(of: Data("https://example.com/private".utf8)) == nil)
    }

    @Test func replacesRecordsAtomicallyAndRemovesOldSearchTerms() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        var snippet = SnippetItem(
            id: UUID(),
            trigger: "old trigger",
            expansion: "Old expansion",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await store.save(snippet, collection: .snippets, searchableText: snippet.trigger)

        snippet.trigger = "new phrase"
        try await store.save(snippet, collection: .snippets, searchableText: snippet.trigger)

        let oldMatches: [SnippetItem] = try await store.fetch(collection: .snippets, matching: "old")
        let newMatches: [SnippetItem] = try await store.fetch(collection: .snippets, matching: "new")
        #expect(oldMatches.isEmpty)
        #expect(newMatches == [snippet])
    }

    @Test func deletionRemovesPayloadAndBlindIndex() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let item = DictionaryItem(
            id: UUID(),
            spokenForm: "super base",
            writtenForm: "Supabase",
            context: .code,
            createdAt: Date()
        )
        try await store.save(item, collection: .dictionary, searchableText: "\(item.spokenForm) \(item.writtenForm)")
        try await store.delete(id: item.id, collection: .dictionary)

        let results: [DictionaryItem] = try await store.fetch(collection: .dictionary, matching: "Supabase")
        #expect(results.isEmpty)
    }

    @Test func backupRestoreAtomicallyReplacesAllUserCollections() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let old = SnippetItem(id: UUID(), trigger: "old", expansion: "Old", createdAt: .now)
        try await store.save(old, collection: .snippets, searchableText: old.trigger)

        let restored = SnippetItem(id: UUID(), trigger: "restored", expansion: "Restored text", createdAt: .now)
        let note = ScratchpadNote(
            id: UUID(),
            title: "Recovered note",
            body: "Recovered body",
            isPinned: true,
            createdAt: .now,
            updatedAt: .now
        )
        let payload = MurmurBackupPayload(
            exportedAt: .now,
            history: [],
            dictionary: [],
            snippets: [restored],
            styles: [],
            notes: [note],
            settings: .default
        )

        try await store.restore(payload)

        let snippets: [SnippetItem] = try await store.fetch(collection: .snippets)
        let notes: [ScratchpadNote] = try await store.fetch(collection: .notes)
        #expect(snippets.map(\.id) == [restored.id])
        #expect(snippets.map(\.expansion) == [restored.expansion])
        #expect(notes.map(\.id) == [note.id])
        #expect(notes.map(\.body) == [note.body])
        #expect(snippets.contains(old) == false)
    }
}

private struct StoreFixture {
    let directoryURL: URL
    let databaseURL: URL
    let key = SymmetricKey(data: Data(repeating: 0x3B, count: 32))

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        databaseURL = directoryURL.appendingPathComponent("store.sqlite")
    }
}
