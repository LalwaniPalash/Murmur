import Foundation
import Testing
@testable import MurmurNext

struct DictationSessionStateMachineTests {
    @Test func followsTheHappyPathExactlyOnce() throws {
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 100)
        let endedAt = Date(timeIntervalSince1970: 104)
        var machine = DictationSessionStateMachine()

        let returnedID = try machine.start(
            id: sessionID,
            mode: .pushToTalk,
            targetBundleIdentifier: "com.example.Editor",
            now: startedAt
        )
        #expect(returnedID == sessionID)
        #expect(machine.session?.phase == .calibrating)

        try machine.beginListening(sessionID: sessionID)
        try machine.updateProvisional("provisional words", sessionID: sessionID)
        try machine.beginFinalizing(sessionID: sessionID)
        try machine.beginInserting(finalText: "Final words.", sessionID: sessionID)
        try machine.complete(sessionID: sessionID, now: endedAt)

        #expect(machine.session?.phase == .completed)
        #expect(machine.session?.finalText == "Final words.")
        #expect(machine.session?.endedAt == endedAt)
        #expect(throws: SessionTransitionError.self) {
            try machine.complete(sessionID: sessionID, now: endedAt)
        }
    }

    @Test func rejectsConcurrentAndStaleSessions() throws {
        let activeID = UUID()
        var machine = DictationSessionStateMachine()
        _ = try machine.start(id: activeID, mode: .handsFree, targetBundleIdentifier: nil)

        #expect(throws: SessionTransitionError.sessionAlreadyActive) {
            try machine.start(mode: .command, targetBundleIdentifier: nil)
        }
        #expect(throws: SessionTransitionError.staleSession) {
            try machine.beginListening(sessionID: UUID())
        }
    }

    @Test func allowsFailureFromAnyNonterminalPhase() throws {
        let sessionID = UUID()
        var machine = DictationSessionStateMachine()
        _ = try machine.start(id: sessionID, mode: .pushToTalk, targetBundleIdentifier: nil)
        try machine.fail(sessionID: sessionID)

        #expect(machine.session?.phase == .failed)
        #expect(machine.session?.endedAt != nil)
    }

    @Test func requiresFinalizationBeforeInsertion() throws {
        let sessionID = UUID()
        var machine = DictationSessionStateMachine()
        _ = try machine.start(id: sessionID, mode: .pushToTalk, targetBundleIdentifier: nil)
        try machine.beginListening(sessionID: sessionID)

        #expect(throws: SessionTransitionError.invalidTransition(from: .listening, to: .inserting)) {
            try machine.beginInserting(finalText: "Too soon", sessionID: sessionID)
        }
    }
}
