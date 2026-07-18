import CryptoKit
import Foundation

enum MurmurTransferError: Error, Equatable, LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)
    case fileTooLarge
    case tooManyItems
    case fieldTooLarge(String)
    case passwordTooShort
    case invalidPasswordOrDamagedBackup
    case unsafeKeyDerivationParameters

    var errorDescription: String? {
        switch self {
        case .invalidFormat: "This file is not a valid Murmur export."
        case .unsupportedVersion(let version): "This Murmur export uses unsupported version \(version)."
        case .fileTooLarge: "The selected Murmur export is larger than the safe import limit."
        case .tooManyItems: "The selected Murmur export contains too many items."
        case .fieldTooLarge(let field): "The \(field) field exceeds Murmur's safe import limit."
        case .passwordTooShort: "Use a backup password with at least 12 characters."
        case .invalidPasswordOrDamagedBackup: "The password is incorrect or the backup is damaged."
        case .unsafeKeyDerivationParameters: "The backup requests unsafe password-processing parameters."
        }
    }
}

struct MurmurLibraryBundle: Codable, Equatable, Sendable {
    let format: String
    let version: Int
    var dictionary: [DictionaryItem]
    var snippets: [SnippetItem]
    var styles: [WritingStyle]

    init(dictionary: [DictionaryItem], snippets: [SnippetItem], styles: [WritingStyle]) {
        format = "murmur-library"
        version = 1
        self.dictionary = dictionary
        self.snippets = snippets
        self.styles = styles
    }
}

struct MurmurLibraryImportPreview: Equatable, Sendable {
    let dictionaryToImport: [DictionaryItem]
    let snippetsToImport: [SnippetItem]
    let stylesToImport: [WritingStyle]
    let duplicateDictionaryCount: Int
    let duplicateSnippetCount: Int

    var hasChanges: Bool {
        dictionaryToImport.isEmpty == false || snippetsToImport.isEmpty == false || stylesToImport.isEmpty == false
    }
}

struct MurmurLibraryTransferService: Sendable {
    private let maximumFileBytes = 64 * 1_024 * 1_024
    private let maximumItemsPerCollection = 10_000
    private let maximumFieldBytes = 1_000_000

    func encode(_ bundle: MurmurLibraryBundle) throws -> Data {
        try validate(bundle)
        return try Self.encoder.encode(bundle)
    }

    func preview(
        _ data: Data,
        existingDictionary: [DictionaryItem],
        existingSnippets: [SnippetItem]
    ) throws -> MurmurLibraryImportPreview {
        guard data.count <= maximumFileBytes else { throw MurmurTransferError.fileTooLarge }
        let bundle: MurmurLibraryBundle
        do {
            bundle = try Self.decoder.decode(MurmurLibraryBundle.self, from: data)
        } catch {
            throw MurmurTransferError.invalidFormat
        }
        guard bundle.format == "murmur-library" else { throw MurmurTransferError.invalidFormat }
        guard bundle.version == 1 else { throw MurmurTransferError.unsupportedVersion(bundle.version) }
        try validate(bundle)

        var dictionaryKeys = Set(existingDictionary.map(Self.dictionaryKey))
        var duplicateDictionaryCount = 0
        let dictionaryToImport = bundle.dictionary.filter { item in
            let inserted = dictionaryKeys.insert(Self.dictionaryKey(item)).inserted
            if inserted == false { duplicateDictionaryCount += 1 }
            return inserted
        }

        var snippetKeys = Set(existingSnippets.map(Self.snippetKey))
        var duplicateSnippetCount = 0
        let snippetsToImport = bundle.snippets.filter { item in
            let inserted = snippetKeys.insert(Self.snippetKey(item)).inserted
            if inserted == false { duplicateSnippetCount += 1 }
            return inserted
        }

        return MurmurLibraryImportPreview(
            dictionaryToImport: dictionaryToImport,
            snippetsToImport: snippetsToImport,
            stylesToImport: bundle.styles,
            duplicateDictionaryCount: duplicateDictionaryCount,
            duplicateSnippetCount: duplicateSnippetCount
        )
    }

    private func validate(_ bundle: MurmurLibraryBundle) throws {
        guard bundle.dictionary.count <= maximumItemsPerCollection,
              bundle.snippets.count <= maximumItemsPerCollection,
              bundle.styles.count <= maximumItemsPerCollection
        else { throw MurmurTransferError.tooManyItems }

        for item in bundle.dictionary {
            try validateField(item.spokenForm, name: "spoken form")
            try validateField(item.writtenForm, name: "written form")
        }
        for item in bundle.snippets {
            try validateField(item.trigger, name: "snippet trigger")
            try validateField(item.expansion, name: "snippet expansion")
        }
        for item in bundle.styles {
            try validateField(item.name, name: "style name")
            try validateField(item.instructions, name: "style instructions")
            guard item.intensity.isFinite, (0...1).contains(item.intensity) else {
                throw MurmurTransferError.invalidFormat
            }
        }
    }

    private func validateField(_ value: String, name: String) throws {
        guard value.utf8.count <= maximumFieldBytes else { throw MurmurTransferError.fieldTooLarge(name) }
    }

    private static func dictionaryKey(_ item: DictionaryItem) -> String {
        [normalize(item.spokenForm), normalize(item.writtenForm), item.context?.rawValue ?? "*"]
            .joined(separator: "|")
    }

    private static func snippetKey(_ item: SnippetItem) -> String {
        normalize(item.trigger)
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

struct MurmurBackupPayload: Codable, Equatable, Sendable {
    let exportedAt: Date
    let history: [TranscriptRecord]
    let dictionary: [DictionaryItem]
    let snippets: [SnippetItem]
    let styles: [WritingStyle]
    let notes: [ScratchpadNote]
    let revisions: [ScratchpadRevision]
    let settings: MurmurSettingsRecord

    init(
        exportedAt: Date,
        history: [TranscriptRecord],
        dictionary: [DictionaryItem],
        snippets: [SnippetItem],
        styles: [WritingStyle],
        notes: [ScratchpadNote],
        revisions: [ScratchpadRevision] = [],
        settings: MurmurSettingsRecord
    ) {
        self.exportedAt = exportedAt
        self.history = history
        self.dictionary = dictionary
        self.snippets = snippets
        self.styles = styles
        self.notes = notes
        self.revisions = revisions
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case exportedAt, history, dictionary, snippets, styles, notes, revisions, settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        history = try container.decode([TranscriptRecord].self, forKey: .history)
        dictionary = try container.decode([DictionaryItem].self, forKey: .dictionary)
        snippets = try container.decode([SnippetItem].self, forKey: .snippets)
        styles = try container.decode([WritingStyle].self, forKey: .styles)
        notes = try container.decode([ScratchpadNote].self, forKey: .notes)
        revisions = try container.decodeIfPresent([ScratchpadRevision].self, forKey: .revisions) ?? []
        settings = try container.decode(MurmurSettingsRecord.self, forKey: .settings)
    }
}

private struct MurmurEncryptedBackupEnvelope: Codable {
    let format: String
    let version: Int
    let keyDerivation: String
    let salt: Data
    let iterations: Int
    let ciphertext: Data
}

struct MurmurBackupService: Sendable {
    let iterations: Int
    private let maximumFileBytes = 256 * 1_024 * 1_024

    init(iterations: Int = 210_000) {
        self.iterations = iterations
    }

    func encrypt(_ payload: MurmurBackupPayload, password: String) throws -> Data {
        let passwordData = Data(password.utf8)
        guard passwordData.count >= 12, passwordData.count <= 1_024 else {
            throw MurmurTransferError.passwordTooShort
        }
        guard (1_000...1_000_000).contains(iterations) else {
            throw MurmurTransferError.unsafeKeyDerivationParameters
        }
        try validate(payload)

        var random = SystemRandomNumberGenerator()
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &random) })
        let key = try Self.deriveKey(password: passwordData, salt: salt, iterations: iterations)
        let plaintext = try Self.payloadEncoder.encode(payload)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw MurmurTransferError.invalidFormat }
        let envelope = MurmurEncryptedBackupEnvelope(
            format: "murmur-encrypted-backup",
            version: 1,
            keyDerivation: "PBKDF2-HMAC-SHA256",
            salt: salt,
            iterations: iterations,
            ciphertext: combined
        )
        return try Self.envelopeEncoder.encode(envelope)
    }

    func decrypt(_ data: Data, password: String) throws -> MurmurBackupPayload {
        guard data.count <= maximumFileBytes else { throw MurmurTransferError.fileTooLarge }
        let envelope: MurmurEncryptedBackupEnvelope
        do {
            envelope = try Self.envelopeDecoder.decode(MurmurEncryptedBackupEnvelope.self, from: data)
        } catch {
            throw MurmurTransferError.invalidFormat
        }
        guard envelope.format == "murmur-encrypted-backup",
              envelope.keyDerivation == "PBKDF2-HMAC-SHA256"
        else { throw MurmurTransferError.invalidFormat }
        guard envelope.version == 1 else { throw MurmurTransferError.unsupportedVersion(envelope.version) }
        guard envelope.salt.count == 16,
              (1_000...1_000_000).contains(envelope.iterations),
              envelope.ciphertext.count >= 28
        else { throw MurmurTransferError.unsafeKeyDerivationParameters }
        guard password.utf8.count <= 1_024 else {
            throw MurmurTransferError.invalidPasswordOrDamagedBackup
        }

        do {
            let key = try Self.deriveKey(
                password: Data(password.utf8),
                salt: envelope.salt,
                iterations: envelope.iterations
            )
            let sealed = try AES.GCM.SealedBox(combined: envelope.ciphertext)
            let plaintext = try AES.GCM.open(sealed, using: key)
            let payload = try Self.payloadDecoder.decode(MurmurBackupPayload.self, from: plaintext)
            try validate(payload)
            return payload
        } catch {
            throw MurmurTransferError.invalidPasswordOrDamagedBackup
        }
    }

    private func validate(_ payload: MurmurBackupPayload) throws {
        guard payload.history.count <= 100_000,
              payload.dictionary.count <= 10_000,
              payload.snippets.count <= 10_000,
              payload.styles.count <= 10_000,
              payload.notes.count <= 10_000,
              payload.revisions.count <= 100_000
        else { throw MurmurTransferError.tooManyItems }

        for record in payload.history {
            try validateBackupField(record.sourceApplication)
            try validateBackupField(record.text)
        }
        for item in payload.dictionary {
            try validateBackupField(item.spokenForm)
            try validateBackupField(item.writtenForm)
        }
        for item in payload.snippets {
            try validateBackupField(item.trigger)
            try validateBackupField(item.expansion)
        }
        for style in payload.styles {
            try validateBackupField(style.name)
            try validateBackupField(style.instructions)
        }
        for note in payload.notes {
            try validateBackupField(note.title)
            try validateBackupField(note.body)
        }
        for revision in payload.revisions {
            try validateBackupField(revision.title)
            try validateBackupField(revision.body)
        }
    }

    private func validateBackupField(_ value: String) throws {
        guard value.utf8.count <= 1_000_000 else {
            throw MurmurTransferError.fieldTooLarge("backup content")
        }
    }

    private static func deriveKey(password: Data, salt: Data, iterations: Int) throws -> SymmetricKey {
        guard password.isEmpty == false else { throw MurmurTransferError.invalidPasswordOrDamagedBackup }
        var blockIndex = UInt32(1).bigEndian
        var firstInput = salt
        Swift.withUnsafeBytes(of: &blockIndex) { firstInput.append(contentsOf: $0) }

        let passwordKey = SymmetricKey(data: password)
        var current = Data(HMAC<SHA256>.authenticationCode(for: firstInput, using: passwordKey))
        var accumulated = current
        if iterations > 1 {
            for _ in 2...iterations {
                current = Data(HMAC<SHA256>.authenticationCode(for: current, using: passwordKey))
                for index in accumulated.indices { accumulated[index] ^= current[index] }
            }
        }
        return SymmetricKey(data: accumulated.prefix(32))
    }

    private static let envelopeEncoder = JSONEncoder()
    private static let envelopeDecoder = JSONDecoder()

    private static let payloadEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let payloadDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
