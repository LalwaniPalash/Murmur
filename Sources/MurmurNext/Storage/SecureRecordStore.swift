import CryptoKit
import Foundation
import Security
import SQLite3

enum MurmurV2Paths {
    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Murmur/v2", isDirectory: true)
    }

    static var databaseURL: URL { rootDirectory.appendingPathComponent("Murmur.sqlite") }
    static var modelsDirectory: URL { rootDirectory.appendingPathComponent("Models", isDirectory: true) }
    static var retainedAudioDirectory: URL { rootDirectory.appendingPathComponent("Audio", isDirectory: true) }
    static var attachmentsDirectory: URL { rootDirectory.appendingPathComponent("Attachments", isDirectory: true) }
    static var backupsDirectory: URL { rootDirectory.appendingPathComponent("Backups", isDirectory: true) }

    static func prepareDirectories() throws {
        for directory in [rootDirectory, modelsDirectory, retainedAudioDirectory, attachmentsDirectory, backupsDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

enum SecureRecordCollection: String, Sendable {
    case settings
    case history
    case dictionary
    case snippets
    case styles
    case notes
    case noteRevisions
    case profiles
    case modelInventory
    case sourceSessions
    case resultVersions
    case retainedAudio
    case recoveryJournals
    case preferredResults
}

enum SecureRecordStoreError: Error, LocalizedError {
    case databaseOpen(String)
    case databaseOperation(String)
    case keychain(OSStatus)
    case malformedCiphertext
    case invalidSessionResultGraph(String)

    var errorDescription: String? {
        switch self {
        case .databaseOpen(let message): "Unable to open Murmur's local database: \(message)"
        case .databaseOperation(let message): "Murmur's local database could not complete an operation: \(message)"
        case .keychain(let status): "Murmur could not access its encryption key (\(status))."
        case .malformedCiphertext: "An encrypted local record is damaged or incomplete."
        case .invalidSessionResultGraph(let message): "Murmur's session history is invalid: \(message)"
        }
    }
}

struct EncryptedPayloadCodec: Sendable {
    private let key: SymmetricKey
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(key: SymmetricKey) {
        self.key = key
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func encrypt<Value: Encodable>(_ value: Value) throws -> Data {
        let plaintext = try encoder.encode(value)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw SecureRecordStoreError.malformedCiphertext
        }
        return combined
    }

    func decrypt<Value: Decodable>(_ encrypted: Data) throws -> Value {
        guard let sealedBox = try? AES.GCM.SealedBox(combined: encrypted) else {
            throw SecureRecordStoreError.malformedCiphertext
        }
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        return try decoder.decode(Value.self, from: plaintext)
    }
}

actor KeychainMasterKeyStore {
    static let shared = KeychainMasterKeyStore()

    private let service = "com.murmur.app.v2"
    private let account = "local-database-master-key"
    private var cachedKey: SymmetricKey?

    func loadOrCreateKey() throws -> SymmetricKey {
        if let cachedKey { return cachedKey }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        }
        guard status == errSecItemNotFound else {
            throw SecureRecordStoreError.keychain(status)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SecureRecordStoreError.keychain(errSecAllocate)
        }
        let data = Data(bytes)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureRecordStoreError.keychain(addStatus)
        }
        let key = SymmetricKey(data: data)
        cachedKey = key
        return key
    }
}

private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer

    init(_ handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }
}

actor SecureRecordStore {
    private struct EncodedRecord {
        let collection: SecureRecordCollection
        let id: UUID
        let createdAt: Date
        let payload: Data
        let searchableText: String
    }

    private let connection: SQLiteConnection
    private let codec: EncryptedPayloadCodec
    private let blindIndexKey: SymmetricKey
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var database: OpaquePointer { connection.handle }

    init(url: URL, key: SymmetricKey) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if let handle { sqlite3_close(handle) }
            throw SecureRecordStoreError.databaseOpen(message)
        }

        connection = SQLiteConnection(handle)
        codec = EncryptedPayloadCodec(key: key)
        blindIndexKey = key
        try Self.configure(database: handle)
        try Self.createSchema(database: handle)
    }

    func save<Value: Codable & Identifiable & Sendable>(
        _ value: Value,
        collection: SecureRecordCollection,
        searchableText: String = ""
    ) throws where Value.ID == UUID {
        let payload = try codec.encrypt(value)
        let createdAt = Self.createdAt(from: value)
        try execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            let upsert = """
                INSERT INTO secure_records(collection, id, created_at, payload)
                VALUES(?, ?, ?, ?)
                ON CONFLICT(collection, id) DO UPDATE SET
                    created_at = excluded.created_at,
                    payload = excluded.payload
                """
            let statement = try prepare(upsert)
            defer { sqlite3_finalize(statement) }
            try bind(collection.rawValue, at: 1, to: statement)
            try bind(value.id.uuidString, at: 2, to: statement)
            sqlite3_bind_double(statement, 3, createdAt.timeIntervalSince1970)
            try bind(payload, at: 4, to: statement)
            try stepDone(statement)

            try deleteSearchTerms(id: value.id, collection: collection)
            for termHash in blindTermHashes(for: searchableText) {
                let insertTerm = try prepare(
                    "INSERT OR IGNORE INTO blind_search_terms(collection, record_id, term_hash) VALUES(?, ?, ?)"
                )
                defer { sqlite3_finalize(insertTerm) }
                try bind(collection.rawValue, at: 1, to: insertTerm)
                try bind(value.id.uuidString, at: 2, to: insertTerm)
                try bind(termHash, at: 3, to: insertTerm)
                try stepDone(insertTerm)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func append(
        session: SourceSessionRecord,
        firstResult: TranscriptResultVersion
    ) throws {
        guard firstResult.sessionID == session.id else {
            throw SecureRecordStoreError.invalidSessionResultGraph(
                "The first result does not belong to its source session."
            )
        }
        guard firstResult.parentResultID == nil else {
            throw SecureRecordStoreError.invalidSessionResultGraph(
                "The first result cannot have a parent."
            )
        }
        let sessionRecord = try encodeRecord(session, collection: .sourceSessions, searchableText: "")
        let resultRecord = try encodeRecord(
            firstResult,
            collection: .resultVersions,
            searchableText: "\(firstResult.rawTranscript) \(firstResult.finalTranscript)"
        )
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try insert(sessionRecord)
            try insert(resultRecord)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func append(result: TranscriptResultVersion) throws {
        guard try recordExists(id: result.sessionID, collection: .sourceSessions) else {
            throw SecureRecordStoreError.invalidSessionResultGraph(
                "The result references a missing source session."
            )
        }
        if let parentID = result.parentResultID {
            guard let parent: TranscriptResultVersion = try fetchRecord(
                id: parentID,
                collection: .resultVersions
            ) else {
                throw SecureRecordStoreError.invalidSessionResultGraph(
                    "The result references a missing parent."
                )
            }
            guard parent.sessionID == result.sessionID else {
                throw SecureRecordStoreError.invalidSessionResultGraph(
                    "The result parent belongs to another source session."
                )
            }
        }
        let record = try encodeRecord(
            result,
            collection: .resultVersions,
            searchableText: "\(result.rawTranscript) \(result.finalTranscript)"
        )
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try insert(record)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func fetchSourceSessions() throws -> [SourceSessionRecord] {
        try fetch(collection: .sourceSessions)
    }

    func fetchResultVersions(matching query: String? = nil) throws -> [TranscriptResultVersion] {
        try fetch(collection: .resultVersions, matching: query)
    }

    func saveRetainedAudio(_ record: RetainedAudioRecord) throws {
        try save(record, collection: .retainedAudio)
    }

    func fetchRetainedAudio() throws -> [RetainedAudioRecord] {
        try fetch(collection: .retainedAudio)
    }

    func deleteRetainedAudio(id: UUID) throws {
        try delete(id: id, collection: .retainedAudio)
    }

    func saveRecoveryJournal(_ record: RecoveryJournalRecord) throws {
        try save(record, collection: .recoveryJournals)
    }

    func fetchRecoveryJournals() throws -> [RecoveryJournalRecord] {
        try fetch(collection: .recoveryJournals)
    }

    func deleteRecoveryJournal(id: UUID) throws {
        try delete(id: id, collection: .recoveryJournals)
    }

    func savePreferredResult(_ record: PreferredResultRecord) throws {
        guard let result: TranscriptResultVersion = try fetchRecord(
            id: record.resultID,
            collection: .resultVersions
        ), result.sessionID == record.sessionID else {
            throw SecureRecordStoreError.invalidSessionResultGraph(
                "The preferred result does not belong to its source session."
            )
        }
        try save(record, collection: .preferredResults)
    }

    func fetchPreferredResults() throws -> [PreferredResultRecord] {
        try fetch(collection: .preferredResults)
    }

    func fetchVersionedHistory(matching query: String? = nil) throws -> [TranscriptRecord] {
        let sessions = try fetchSourceSessions()
        let allResults = try fetchResultVersions()
        let preferredBySession = Dictionary(
            uniqueKeysWithValues: try fetchPreferredResults().map { ($0.sessionID, $0.resultID) }
        )
        let includedSessionIDs: Set<UUID>
        if let query, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            includedSessionIDs = Set(try fetchResultVersions(matching: query).map(\.sessionID))
        } else {
            includedSessionIDs = Set(sessions.map(\.id))
        }
        return try sessions
            .filter { includedSessionIDs.contains($0.id) }
            .map {
                try SessionResultProjection.history(
                    session: $0,
                    results: allResults,
                    preferredResultID: preferredBySession[$0.id]
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func schemaVersion() throws -> Int {
        let statement = try prepare("SELECT version FROM schema_metadata LIMIT 1")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw operationError() }
        return Int(sqlite3_column_int(statement, 0))
    }

    func migrateHistoryToVersionedRecordsIfNeeded() throws {
        guard try schemaVersion() < 2 else { return }
        let legacy: [TranscriptRecord] = try fetch(collection: .history)
        let converted = legacy.map(LegacySessionResultConverter.convert)
        let records = try converted.flatMap { conversion in
            [
                try encodeRecord(
                    conversion.session,
                    collection: .sourceSessions,
                    searchableText: ""
                ),
                try encodeRecord(
                    conversion.result,
                    collection: .resultVersions,
                    searchableText: "\(conversion.result.rawTranscript) \(conversion.result.finalTranscript)"
                ),
            ]
        }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for record in records { try insert(record) }
            try execute("UPDATE schema_metadata SET version = 2")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func fetch<Value: Decodable & Sendable>(
        collection: SecureRecordCollection,
        matching query: String? = nil,
        limit: Int = 10_000
    ) throws -> [Value] {
        let hashes = blindTermHashes(for: query ?? "")
        let statement: OpaquePointer

        if hashes.isEmpty {
            statement = try prepare(
                "SELECT payload FROM secure_records WHERE collection = ? ORDER BY created_at DESC LIMIT ?"
            )
            try bind(collection.rawValue, at: 1, to: statement)
            sqlite3_bind_int(statement, 2, Int32(clamping: limit))
        } else {
            let placeholders = Array(repeating: "?", count: hashes.count).joined(separator: ",")
            statement = try prepare(
                """
                SELECT records.payload
                FROM secure_records AS records
                INNER JOIN blind_search_terms AS terms
                    ON terms.collection = records.collection AND terms.record_id = records.id
                WHERE records.collection = ? AND terms.term_hash IN (\(placeholders))
                GROUP BY records.collection, records.id
                HAVING COUNT(DISTINCT terms.term_hash) = ?
                ORDER BY records.created_at DESC
                LIMIT ?
                """
            )
            try bind(collection.rawValue, at: 1, to: statement)
            for (offset, hash) in hashes.enumerated() {
                try bind(hash, at: Int32(offset + 2), to: statement)
            }
            sqlite3_bind_int(statement, Int32(hashes.count + 2), Int32(hashes.count))
            sqlite3_bind_int(statement, Int32(hashes.count + 3), Int32(clamping: limit))
        }
        defer { sqlite3_finalize(statement) }

        var values: [Value] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw operationError() }
            guard let bytes = sqlite3_column_blob(statement, 0) else {
                throw SecureRecordStoreError.malformedCiphertext
            }
            let count = Int(sqlite3_column_bytes(statement, 0))
            let encrypted = Data(bytes: bytes, count: count)
            values.append(try codec.decrypt(encrypted))
        }
        return values
    }

    func delete(id: UUID, collection: SecureRecordCollection) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try deleteRecord(id: id, collection: collection)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteSession(id: UUID) throws {
        let resultIDs = try fetchResultVersions().filter { $0.sessionID == id }.map(\.id)
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for resultID in resultIDs {
                try deleteRecord(id: resultID, collection: .resultVersions)
            }
            try deleteRecord(id: id, collection: .sourceSessions)
            try deleteRecord(id: id, collection: .preferredResults)
            try deleteRecord(id: id, collection: .history)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func restore(_ backup: MurmurBackupPayload) throws {
        let restoredSessions: [SourceSessionRecord]
        let restoredResults: [TranscriptResultVersion]
        if backup.sourceSessions.isEmpty && backup.resultVersions.isEmpty {
            let conversions = backup.history.map(LegacySessionResultConverter.convert)
            restoredSessions = conversions.map(\.session)
            restoredResults = conversions.map(\.result)
        } else {
            restoredSessions = backup.sourceSessions
            restoredResults = backup.resultVersions
        }
        do {
            try SessionResultGraphValidator.validate(
                sessions: restoredSessions,
                results: restoredResults
            )
        } catch {
            throw SecureRecordStoreError.invalidSessionResultGraph(error.localizedDescription)
        }
        let restoredResultsByID = Dictionary(uniqueKeysWithValues: restoredResults.map { ($0.id, $0) })
        guard Set(backup.preferredResults.map(\.sessionID)).count == backup.preferredResults.count,
              backup.preferredResults.allSatisfy({ preference in
                  restoredResultsByID[preference.resultID]?.sessionID == preference.sessionID
              })
        else {
            throw SecureRecordStoreError.invalidSessionResultGraph(
                "A preferred result does not belong to its source session."
            )
        }

        var records: [EncodedRecord] = []
        records += try backup.history.map {
            try encodeRecord($0, collection: .history, searchableText: "\($0.sourceApplication) \($0.text)")
        }
        records += try backup.dictionary.map {
            try encodeRecord($0, collection: .dictionary, searchableText: "\($0.spokenForm) \($0.writtenForm)")
        }
        records += try backup.snippets.map {
            try encodeRecord($0, collection: .snippets, searchableText: "\($0.trigger) \($0.expansion)")
        }
        records += try backup.styles.map {
            try encodeRecord($0, collection: .styles, searchableText: "\($0.name) \($0.instructions)")
        }
        records += try backup.notes.map {
            try encodeRecord($0, collection: .notes, searchableText: "\($0.title) \($0.body)")
        }
        records += try backup.revisions.map {
            try encodeRecord($0, collection: .noteRevisions, searchableText: "")
        }
        records.append(try encodeRecord(backup.settings, collection: .settings, searchableText: ""))
        records += try restoredSessions.map {
            try encodeRecord($0, collection: .sourceSessions, searchableText: "")
        }
        records += try restoredResults.map {
            try encodeRecord(
                $0,
                collection: .resultVersions,
                searchableText: "\($0.rawTranscript) \($0.finalTranscript)"
            )
        }
        records += try backup.preferredResults.map {
            try encodeRecord($0, collection: .preferredResults, searchableText: "")
        }

        let replacedCollections: [SecureRecordCollection] = [
            .settings, .history, .dictionary, .snippets, .styles, .notes, .noteRevisions,
            .sourceSessions, .resultVersions, .preferredResults,
        ]
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for collection in replacedCollections {
                let statement = try prepare("DELETE FROM secure_records WHERE collection = ?")
                try bind(collection.rawValue, at: 1, to: statement)
                do {
                    try stepDone(statement)
                    sqlite3_finalize(statement)
                } catch {
                    sqlite3_finalize(statement)
                    throw error
                }
            }
            for record in records { try insert(record) }
            try execute("UPDATE schema_metadata SET version = 2")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func encodeRecord<Value: Codable & Identifiable>(
        _ value: Value,
        collection: SecureRecordCollection,
        searchableText: String
    ) throws -> EncodedRecord where Value.ID == UUID {
        EncodedRecord(
            collection: collection,
            id: value.id,
            createdAt: Self.createdAt(from: value),
            payload: try codec.encrypt(value),
            searchableText: searchableText
        )
    }

    private func insert(_ record: EncodedRecord) throws {
        let statement = try prepare(
            "INSERT INTO secure_records(collection, id, created_at, payload) VALUES(?, ?, ?, ?)"
        )
        defer { sqlite3_finalize(statement) }
        try bind(record.collection.rawValue, at: 1, to: statement)
        try bind(record.id.uuidString, at: 2, to: statement)
        sqlite3_bind_double(statement, 3, record.createdAt.timeIntervalSince1970)
        try bind(record.payload, at: 4, to: statement)
        try stepDone(statement)

        for termHash in blindTermHashes(for: record.searchableText) {
            let termStatement = try prepare(
                "INSERT INTO blind_search_terms(collection, record_id, term_hash) VALUES(?, ?, ?)"
            )
            defer { sqlite3_finalize(termStatement) }
            try bind(record.collection.rawValue, at: 1, to: termStatement)
            try bind(record.id.uuidString, at: 2, to: termStatement)
            try bind(termHash, at: 3, to: termStatement)
            try stepDone(termStatement)
        }
    }

    private func blindTermHashes(for text: String) -> [Data] {
        let terms = Set(
            text.lowercased()
                .split(whereSeparator: { $0.isLetter == false && $0.isNumber == false })
                .map(String.init)
                .filter { $0.count >= 2 }
        )
        return terms.sorted().map { term in
            let code = HMAC<SHA256>.authenticationCode(for: Data(term.utf8), using: blindIndexKey)
            return Data(code.prefix(16))
        }
    }

    private func deleteSearchTerms(id: UUID, collection: SecureRecordCollection) throws {
        let statement = try prepare("DELETE FROM blind_search_terms WHERE collection = ? AND record_id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(collection.rawValue, at: 1, to: statement)
        try bind(id.uuidString, at: 2, to: statement)
        try stepDone(statement)
    }

    private func deleteRecord(id: UUID, collection: SecureRecordCollection) throws {
        try deleteSearchTerms(id: id, collection: collection)
        let statement = try prepare("DELETE FROM secure_records WHERE collection = ? AND id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(collection.rawValue, at: 1, to: statement)
        try bind(id.uuidString, at: 2, to: statement)
        try stepDone(statement)
    }

    private func recordExists(id: UUID, collection: SecureRecordCollection) throws -> Bool {
        let statement = try prepare(
            "SELECT 1 FROM secure_records WHERE collection = ? AND id = ? LIMIT 1"
        )
        defer { sqlite3_finalize(statement) }
        try bind(collection.rawValue, at: 1, to: statement)
        try bind(id.uuidString, at: 2, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw operationError() }
        return result == SQLITE_ROW
    }

    private func fetchRecord<Value: Decodable>(
        id: UUID,
        collection: SecureRecordCollection
    ) throws -> Value? {
        let statement = try prepare(
            "SELECT payload FROM secure_records WHERE collection = ? AND id = ? LIMIT 1"
        )
        defer { sqlite3_finalize(statement) }
        try bind(collection.rawValue, at: 1, to: statement)
        try bind(id.uuidString, at: 2, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
            throw operationError()
        }
        let count = Int(sqlite3_column_bytes(statement, 0))
        return try codec.decrypt(Data(bytes: bytes, count: count))
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SecureRecordStoreError.databaseOperation(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw operationError()
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw operationError()
        }
    }

    private func bind(_ value: Data, at index: Int32, to statement: OpaquePointer) throws {
        let status = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), sqliteTransient)
        }
        guard status == SQLITE_OK else { throw operationError() }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw operationError() }
    }

    private func operationError() -> SecureRecordStoreError {
        SecureRecordStoreError.databaseOperation(String(cString: sqlite3_errmsg(database)))
    }

    private static func configure(database: OpaquePointer) throws {
        try execute(database: database, sql: "PRAGMA journal_mode = WAL")
        try execute(database: database, sql: "PRAGMA foreign_keys = ON")
        try execute(database: database, sql: "PRAGMA synchronous = FULL")
        try execute(database: database, sql: "PRAGMA secure_delete = ON")
    }

    private static func createSchema(database: OpaquePointer) throws {
        try execute(
            database: database,
            sql: """
            CREATE TABLE IF NOT EXISTS schema_metadata(
                version INTEGER NOT NULL
            );
            INSERT INTO schema_metadata(version)
                SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema_metadata);

            CREATE TABLE IF NOT EXISTS secure_records(
                collection TEXT NOT NULL,
                id TEXT NOT NULL,
                created_at REAL NOT NULL,
                payload BLOB NOT NULL,
                PRIMARY KEY(collection, id)
            );

            CREATE TABLE IF NOT EXISTS blind_search_terms(
                collection TEXT NOT NULL,
                record_id TEXT NOT NULL,
                term_hash BLOB NOT NULL,
                PRIMARY KEY(collection, record_id, term_hash),
                FOREIGN KEY(collection, record_id)
                    REFERENCES secure_records(collection, id)
                    ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS blind_search_lookup
                ON blind_search_terms(collection, term_hash);
            CREATE INDEX IF NOT EXISTS secure_records_created
                ON secure_records(collection, created_at DESC);
            """
        )
    }

    private static func execute(database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SecureRecordStoreError.databaseOperation(message)
        }
    }

    private static func createdAt<Value>(from value: Value) -> Date {
        switch value {
        case let value as TranscriptRecord: value.createdAt
        case let value as DictionaryItem: value.createdAt
        case let value as SnippetItem: value.createdAt
        case let value as ScratchpadNote: value.createdAt
        case let value as ScratchpadRevision: value.createdAt
        case let value as SourceSessionRecord: value.startedAt
        case let value as TranscriptResultVersion: value.createdAt
        case let value as RetainedAudioRecord: value.createdAt
        case let value as RecoveryJournalRecord: value.updatedAt
        case let value as PreferredResultRecord: value.updatedAt
        case is MurmurSettingsRecord: Date(timeIntervalSince1970: 0)
        default: Date()
        }
    }
}
