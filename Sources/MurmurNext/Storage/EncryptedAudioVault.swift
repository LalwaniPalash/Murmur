import CryptoKit
import Foundation

enum EncryptedAudioVaultError: Error, Equatable, LocalizedError {
    case invalidPath
    case captureAlreadyExists
    case captureNotFound
    case invalidFormat
    case unsupportedVersion(Int)
    case invalidSampleRate
    case invalidChunk
    case authenticationFailed
    case truncated
    case metadataMismatch

    var errorDescription: String? {
        switch self {
        case .invalidPath: "The encrypted recording path is invalid."
        case .captureAlreadyExists: "An encrypted recording already exists for this session."
        case .captureNotFound: "The encrypted recording session is unavailable."
        case .invalidFormat: "The encrypted recording has an invalid format."
        case .unsupportedVersion(let version): "Encrypted recording version \(version) is unsupported."
        case .invalidSampleRate: "The encrypted recording has an invalid sample rate."
        case .invalidChunk: "The encrypted recording contains an invalid audio chunk."
        case .authenticationFailed: "The encrypted recording could not be authenticated."
        case .truncated: "The encrypted recording is incomplete."
        case .metadataMismatch: "The encrypted recording does not match its protected metadata."
        }
    }
}

actor EncryptedAudioVault {
    struct LegacyRecording: Sendable {
        let sessionID: UUID
        let createdAt: Date
        let sampleRate: Int
        let samples: [Float]
    }

    private struct Header: Codable, Equatable {
        let version: Int
        let sessionID: UUID
        let sampleRate: Int
        let sampleFormat: String
    }

    private struct ActiveCapture {
        var record: RetainedAudioRecord
        let key: SymmetricKey
        let headerData: Data
        let fileHandle: FileHandle
        var sampleCount: Int
        var chunkCount: Int
    }

    private static let magic = Data("MRA2".utf8)
    private static let formatVersion = 2
    private static let maximumHeaderBytes = 4_096
    private static let maximumChunkBytes = 8 * 1_024 * 1_024
    private static let maximumSamplesPerChunk = 1_000_000

    private let rootURL: URL
    private let masterKey: SymmetricKey
    private var captures: [UUID: ActiveCapture] = [:]

    init(rootURL: URL, masterKey: SymmetricKey) {
        self.rootURL = rootURL.standardizedFileURL
        self.masterKey = masterKey
    }

    func beginCapture(
        sessionID: UUID,
        sampleRate: Int,
        createdAt: Date,
        expiresAt: Date?
    ) throws -> RetainedAudioRecord {
        guard (8_000...384_000).contains(sampleRate) else {
            throw EncryptedAudioVaultError.invalidSampleRate
        }
        guard captures[sessionID] == nil else {
            throw EncryptedAudioVaultError.captureAlreadyExists
        }
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        let partialName = Self.partialFileName(for: sessionID)
        let partialURL = try resolvedURL(relativePath: partialName, sessionID: sessionID, state: .capturing)
        guard FileManager.default.fileExists(atPath: partialURL.path) == false else {
            throw EncryptedAudioVaultError.captureAlreadyExists
        }

        let rawKey = SymmetricKey(size: .bits256)
        let rawKeyData = rawKey.withUnsafeBytes { Data($0) }
        let wrappedBox = try AES.GCM.seal(rawKeyData, using: masterKey)
        guard let wrappedKey = wrappedBox.combined else {
            throw EncryptedAudioVaultError.invalidFormat
        }
        let header = Header(
            version: Self.formatVersion,
            sessionID: sessionID,
            sampleRate: sampleRate,
            sampleFormat: "float32-le"
        )
        let headerData = try Self.encoder.encode(header)
        guard headerData.count <= Self.maximumHeaderBytes else {
            throw EncryptedAudioVaultError.invalidFormat
        }
        var fileData = Self.magic
        fileData.append(Self.bigEndianData(UInt32(headerData.count)))
        fileData.append(headerData)
        try fileData.write(to: partialURL, options: [.atomic, .completeFileProtection])
        let handle = try FileHandle(forWritingTo: partialURL)
        try handle.seekToEnd()

        let record = RetainedAudioRecord(
            id: sessionID,
            createdAt: createdAt,
            expiresAt: expiresAt,
            relativePath: partialName,
            wrappedKey: wrappedKey,
            sampleRate: sampleRate
        )
        captures[sessionID] = ActiveCapture(
            record: record,
            key: rawKey,
            headerData: headerData,
            fileHandle: handle,
            sampleCount: 0,
            chunkCount: 0
        )
        return record
    }

    func append(_ samples: [Float], sessionID: UUID) throws {
        guard samples.isEmpty == false, samples.count <= Self.maximumSamplesPerChunk else {
            throw EncryptedAudioVaultError.invalidChunk
        }
        guard var capture = captures.removeValue(forKey: sessionID) else {
            throw EncryptedAudioVaultError.captureNotFound
        }
        do {
            let plaintext = Self.encode(samples: samples)
            let associatedData = Self.associatedData(
                headerData: capture.headerData,
                chunkIndex: capture.chunkCount
            )
            let sealed = try AES.GCM.seal(
                plaintext,
                using: capture.key,
                authenticating: associatedData
            )
            guard let combined = sealed.combined,
                  combined.count <= Self.maximumChunkBytes
            else { throw EncryptedAudioVaultError.invalidChunk }
            var framed = Self.bigEndianData(UInt32(combined.count))
            framed.append(combined)
            try capture.fileHandle.write(contentsOf: framed)
            capture.sampleCount += samples.count
            capture.chunkCount += 1
            captures[sessionID] = capture
        } catch {
            captures[sessionID] = capture
            throw error
        }
    }

    func finalize(sessionID: UUID) throws -> RetainedAudioRecord {
        guard let capture = captures.removeValue(forKey: sessionID) else {
            throw EncryptedAudioVaultError.captureNotFound
        }
        try capture.fileHandle.synchronize()
        try capture.fileHandle.close()
        let partialURL = try resolvedURL(
            relativePath: capture.record.relativePath,
            sessionID: sessionID,
            state: .capturing
        )
        let finalName = Self.finalFileName(for: sessionID)
        let finalURL = try resolvedURL(relativePath: finalName, sessionID: sessionID, state: .sealed)
        guard FileManager.default.fileExists(atPath: finalURL.path) == false else {
            throw EncryptedAudioVaultError.captureAlreadyExists
        }
        try FileManager.default.moveItem(at: partialURL, to: finalURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return RetainedAudioRecord(
            id: capture.record.id,
            createdAt: capture.record.createdAt,
            expiresAt: capture.record.expiresAt,
            relativePath: finalName,
            wrappedKey: capture.record.wrappedKey,
            sampleRate: capture.record.sampleRate,
            sampleCount: capture.sampleCount,
            chunkCount: capture.chunkCount,
            byteCount: byteCount,
            state: .sealed
        )
    }

    func cancel(sessionID: UUID, deleteCiphertext: Bool) throws {
        guard let capture = captures.removeValue(forKey: sessionID) else { return }
        try? capture.fileHandle.close()
        guard deleteCiphertext else { return }
        let url = try resolvedURL(
            relativePath: capture.record.relativePath,
            sessionID: sessionID,
            state: .capturing
        )
        try? FileManager.default.removeItem(at: url)
    }

    func samples(for record: RetainedAudioRecord) throws -> [Float] {
        guard record.state == .sealed else { throw EncryptedAudioVaultError.metadataMismatch }
        return try read(record: record, allowsIncompleteTail: false)
    }

    func recoverPartialSamples(for record: RetainedAudioRecord) throws -> [Float] {
        guard record.state == .capturing else { throw EncryptedAudioVaultError.metadataMismatch }
        return try read(record: record, allowsIncompleteTail: true)
    }

    func deleteCiphertext(for record: RetainedAudioRecord) throws {
        let url = try resolvedURL(
            relativePath: record.relativePath,
            sessionID: record.id,
            state: record.state
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func legacyRecordings() throws -> [LegacyRecording] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            guard url.pathExtension.lowercased() == "wav",
                  let sessionID = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else { return nil }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            let decoded = try Self.decodeLegacyWave(Data(contentsOf: url))
            return LegacyRecording(
                sessionID: sessionID,
                createdAt: values.contentModificationDate ?? Date(),
                sampleRate: decoded.sampleRate,
                samples: decoded.samples
            )
        }
    }

    func deleteLegacyRecording(sessionID: UUID) throws {
        let candidates = [
            "\(sessionID.uuidString).wav",
            "\(sessionID.uuidString.lowercased()).wav",
        ]
        for name in candidates {
            let url = rootURL.appendingPathComponent(name).standardizedFileURL
            guard url.deletingLastPathComponent() == rootURL else {
                throw EncryptedAudioVaultError.invalidPath
            }
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    func removeOrphanedCiphertext(keeping relativePaths: Set<String>) throws {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            let name = url.lastPathComponent
            let isEncryptedAudio = name.hasSuffix(".mra") || name.hasSuffix(".mra.partial")
            guard isEncryptedAudio, relativePaths.contains(name) == false else { continue }
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            try FileManager.default.removeItem(at: url)
        }
    }

    func simulateInterruptedTailForTesting(sessionID: UUID) throws {
        guard let capture = captures[sessionID] else {
            throw EncryptedAudioVaultError.captureNotFound
        }
        try capture.fileHandle.write(contentsOf: Data([0, 0]))
        try capture.fileHandle.synchronize()
    }

    private func read(
        record: RetainedAudioRecord,
        allowsIncompleteTail: Bool
    ) throws -> [Float] {
        let url = try resolvedURL(
            relativePath: record.relativePath,
            sessionID: record.id,
            state: record.state
        )
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let parsed = try Self.parseHeader(from: data)
        guard parsed.header.sessionID == record.id,
              parsed.header.sampleRate == record.sampleRate,
              parsed.header.sampleFormat == "float32-le"
        else { throw EncryptedAudioVaultError.metadataMismatch }

        let key: SymmetricKey
        do {
            let wrappedBox = try AES.GCM.SealedBox(combined: record.wrappedKey)
            let rawKey = try AES.GCM.open(wrappedBox, using: masterKey)
            guard rawKey.count == 32 else { throw EncryptedAudioVaultError.authenticationFailed }
            key = SymmetricKey(data: rawKey)
        } catch {
            throw EncryptedAudioVaultError.authenticationFailed
        }

        var offset = parsed.payloadOffset
        var chunkIndex = 0
        var samples: [Float] = []
        while offset < data.count {
            guard data.count - offset >= 4 else {
                if allowsIncompleteTail { break }
                throw EncryptedAudioVaultError.truncated
            }
            let length = Int(Self.readUInt32(data, at: offset))
            offset += 4
            guard length >= 28, length <= Self.maximumChunkBytes else {
                if allowsIncompleteTail && data.count - offset < length { break }
                throw EncryptedAudioVaultError.invalidChunk
            }
            guard data.count - offset >= length else {
                if allowsIncompleteTail { break }
                throw EncryptedAudioVaultError.truncated
            }
            let encrypted = data.subdata(in: offset..<(offset + length))
            offset += length
            do {
                let box = try AES.GCM.SealedBox(combined: encrypted)
                let plaintext = try AES.GCM.open(
                    box,
                    using: key,
                    authenticating: Self.associatedData(
                        headerData: parsed.headerData,
                        chunkIndex: chunkIndex
                    )
                )
                samples.append(contentsOf: try Self.decodeSamples(plaintext))
            } catch let error as EncryptedAudioVaultError {
                throw error
            } catch {
                throw EncryptedAudioVaultError.authenticationFailed
            }
            chunkIndex += 1
        }

        if record.state == .sealed {
            guard chunkIndex == record.chunkCount,
                  samples.count == record.sampleCount,
                  data.count == record.byteCount
            else { throw EncryptedAudioVaultError.metadataMismatch }
        }
        return samples
    }

    private func resolvedURL(
        relativePath: String,
        sessionID: UUID,
        state: RetainedAudioState
    ) throws -> URL {
        let expected = state == .capturing
            ? Self.partialFileName(for: sessionID)
            : Self.finalFileName(for: sessionID)
        guard relativePath == expected,
              URL(fileURLWithPath: relativePath).lastPathComponent == relativePath
        else { throw EncryptedAudioVaultError.invalidPath }
        let resolved = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard resolved.deletingLastPathComponent() == rootURL else {
            throw EncryptedAudioVaultError.invalidPath
        }
        return resolved
    }

    private static func parseHeader(
        from data: Data
    ) throws -> (header: Header, headerData: Data, payloadOffset: Int) {
        guard data.count >= 8, data.prefix(4) == magic else {
            throw EncryptedAudioVaultError.invalidFormat
        }
        let length = Int(readUInt32(data, at: 4))
        guard length > 0, length <= maximumHeaderBytes, data.count >= 8 + length else {
            throw EncryptedAudioVaultError.truncated
        }
        let headerData = data.subdata(in: 8..<(8 + length))
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: headerData)
        } catch {
            throw EncryptedAudioVaultError.invalidFormat
        }
        guard header.version == formatVersion else {
            throw EncryptedAudioVaultError.unsupportedVersion(header.version)
        }
        guard (8_000...384_000).contains(header.sampleRate) else {
            throw EncryptedAudioVaultError.invalidSampleRate
        }
        return (header, headerData, 8 + length)
    }

    private static func associatedData(headerData: Data, chunkIndex: Int) -> Data {
        var data = headerData
        data.append(bigEndianData(UInt64(chunkIndex)))
        return data
    }

    private static func encode(samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 4)
        for sample in samples {
            var bits = sample.bitPattern.littleEndian
            Swift.withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func decodeSamples(_ data: Data) throws -> [Float] {
        guard data.count.isMultiple(of: 4),
              data.count / 4 <= maximumSamplesPerChunk
        else { throw EncryptedAudioVaultError.invalidChunk }
        var result: [Float] = []
        result.reserveCapacity(data.count / 4)
        var offset = 0
        while offset < data.count {
            let bits = UInt32(data[offset])
                | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16
                | UInt32(data[offset + 3]) << 24
            result.append(Float(bitPattern: bits))
            offset += 4
        }
        return result
    }

    private static func decodeLegacyWave(_ data: Data) throws -> (sampleRate: Int, samples: [Float]) {
        guard data.count >= 44,
              data.subdata(in: 0..<4) == Data("RIFF".utf8),
              data.subdata(in: 8..<12) == Data("WAVE".utf8),
              data.subdata(in: 12..<16) == Data("fmt ".utf8),
              readUInt16LittleEndian(data, at: 20) == 1,
              readUInt16LittleEndian(data, at: 22) == 1,
              readUInt16LittleEndian(data, at: 34) == 16,
              data.subdata(in: 36..<40) == Data("data".utf8)
        else { throw EncryptedAudioVaultError.invalidFormat }
        let sampleRate = Int(readUInt32LittleEndian(data, at: 24))
        let byteCount = Int(readUInt32LittleEndian(data, at: 40))
        guard (8_000...384_000).contains(sampleRate),
              byteCount.isMultiple(of: 2),
              byteCount <= data.count - 44
        else { throw EncryptedAudioVaultError.invalidFormat }
        var samples: [Float] = []
        samples.reserveCapacity(byteCount / 2)
        var offset = 44
        while offset < 44 + byteCount {
            let bits = readUInt16LittleEndian(data, at: offset)
            samples.append(Float(Int16(bitPattern: bits)) / Float(Int16.max))
            offset += 2
        }
        return (sampleRate, samples)
    }

    private static func bigEndianData<Value: FixedWidthInteger>(_ value: Value) -> Data {
        var value = value.bigEndian
        return Swift.withUnsafeBytes(of: &value) { Data($0) }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    private static func readUInt16LittleEndian(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readUInt32LittleEndian(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func partialFileName(for sessionID: UUID) -> String {
        "\(sessionID.uuidString.lowercased()).mra.partial"
    }

    private static func finalFileName(for sessionID: UUID) -> String {
        "\(sessionID.uuidString.lowercased()).mra"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
