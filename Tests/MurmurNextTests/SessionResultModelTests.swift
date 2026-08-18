import Foundation
import Testing

@testable import MurmurNext

struct SessionResultModelTests {
    @Test func projectsNewestResultIntoExistingHistoryShape() throws {
        let session = Self.session()
        let first = Self.result(
            id: UUID(),
            sessionID: session.id,
            createdAt: Date(timeIntervalSince1970: 110),
            raw: "Meet Tuesday, sorry, Wednesday.",
            final: "Meet Wednesday.",
            insertionSucceeded: false
        )
        let newest = Self.result(
            id: UUID(),
            sessionID: session.id,
            parentResultID: first.id,
            createdAt: Date(timeIntervalSince1970: 120),
            raw: "Meet Wednesday.",
            final: "Meet Wednesday at three.",
            insertionSucceeded: true
        )

        let projection = try SessionResultProjection.history(
            session: session,
            results: [first, newest]
        )

        #expect(projection.id == session.id)
        #expect(projection.createdAt == session.startedAt)
        #expect(projection.sourceApplication == session.sourceApplication)
        #expect(projection.text == newest.finalTranscript)
        #expect(projection.insertionSucceeded)
        #expect(projection.duration == 12)
    }

    @Test func resultSelectionIsDeterministicWhenTimestampsMatch() throws {
        let session = Self.session()
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let date = Date(timeIntervalSince1970: 120)
        let earlier = Self.result(id: earlierID, sessionID: session.id, createdAt: date, final: "First")
        let later = Self.result(id: laterID, sessionID: session.id, createdAt: date, final: "Second")

        let preferred = try SessionResultProjection.preferredResult(
            for: session.id,
            results: [later, earlier]
        )

        #expect(preferred.id == laterID)
    }

    @Test func rejectsMissingAndCrossSessionResults() {
        let session = Self.session()
        #expect(throws: SessionResultProjectionError.missingResult(session.id)) {
            try SessionResultProjection.history(session: session, results: [])
        }

        let foreign = Self.result(id: UUID(), sessionID: UUID(), createdAt: .now, final: "Foreign")
        #expect(throws: SessionResultProjectionError.missingResult(session.id)) {
            try SessionResultProjection.history(session: session, results: [foreign])
        }
    }

    @Test func convertsLegacyHistoryWithoutInventingProvenance() {
        let legacy = TranscriptRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            sourceApplication: "Mail",
            sourceBundleIdentifier: "com.apple.mail",
            context: .email,
            mode: .pushToTalk,
            text: "Legacy final text.",
            duration: 4,
            wordsPerMinute: 45,
            insertionSucceeded: true
        )

        let converted = LegacySessionResultConverter.convert(legacy)

        #expect(converted.session.id == legacy.id)
        #expect(converted.result.id == legacy.id)
        #expect(converted.result.sessionID == legacy.id)
        #expect(converted.result.rawTranscript == legacy.text)
        #expect(converted.result.finalTranscript == legacy.text)
        #expect(converted.result.providerIdentifier == SessionResultProvenance.legacyUnknown)
        #expect(converted.result.modelIdentifier == SessionResultProvenance.legacyUnknown)
        #expect(converted.result.language == SessionResultProvenance.legacyUnknown)
    }

    @Test func decodesVersionOneResultWithoutTransformationProvenance() throws {
        let result = Self.result(
            id: UUID(),
            sessionID: UUID(),
            createdAt: Date(timeIntervalSince1970: 120),
            final: "Complete legacy result."
        )
        let encoded = try JSONEncoder().encode(result)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 1
        object.removeValue(forKey: "writingTransformation")

        let decoded = try JSONDecoder().decode(
            TranscriptResultVersion.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.finalTranscript == "Complete legacy result.")
        #expect(decoded.writingTransformation == nil)
    }

    private static func session() -> SourceSessionRecord {
        SourceSessionRecord(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 112),
            sourceApplication: "Mail",
            sourceBundleIdentifier: "com.apple.mail",
            context: .email,
            mode: .pushToTalk,
            recordingDuration: 12
        )
    }

    private static func result(
        id: UUID,
        sessionID: UUID,
        parentResultID: UUID? = nil,
        createdAt: Date,
        raw: String = "Raw words.",
        final: String,
        insertionSucceeded: Bool = true
    ) -> TranscriptResultVersion {
        TranscriptResultVersion(
            id: id,
            sessionID: sessionID,
            parentResultID: parentResultID,
            createdAt: createdAt,
            rawTranscript: raw,
            finalTranscript: final,
            providerIdentifier: "local-whisper",
            modelIdentifier: "small.en",
            language: "en",
            totalProcessingDuration: 0.4,
            insertionSucceeded: insertionSucceeded
        )
    }
}
