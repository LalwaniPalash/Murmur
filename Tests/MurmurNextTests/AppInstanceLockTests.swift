import Foundation
import Testing
@testable import MurmurNext

@Suite(.serialized)
struct AppInstanceLockTests {
    @Test
    func onlyOneOwnerCanHoldTheCaptureLock() throws {
        let fixture = try LockFixture()
        let first = AppInstanceLock(url: fixture.url)
        let second = AppInstanceLock(url: fixture.url)

        #expect(try first.acquire())
        #expect(try second.acquire() == false)
        #expect(first.isOwner)
        #expect(second.isOwner == false)

        first.release()
        #expect(try second.acquire())
        #expect(second.isOwner)
    }

    @Test
    func releasingOrDeinitializingAllowsStaleLockRecovery() throws {
        let fixture = try LockFixture()
        do {
            let first = AppInstanceLock(url: fixture.url)
            #expect(try first.acquire())
        }

        let replacement = AppInstanceLock(url: fixture.url)
        #expect(try replacement.acquire())
    }
}

private struct LockFixture {
    let url: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-instance-lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("capture.lock")
    }
}
