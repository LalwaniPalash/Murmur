import Foundation
import Testing
@testable import MurmurNext

struct ProviderCredentialStoreTests {
    @Test func savesReplacesDetectsAndDeletesWithoutPublishingTheSecret() async throws {
        let backend = InMemoryCredentialBackend()
        let store = ProviderCredentialStore(backend: backend)

        #expect(try await store.contains(providerIdentifier: "openai") == false)
        try await store.save("sk-first", providerIdentifier: "openai")
        #expect(try await store.contains(providerIdentifier: "openai"))
        #expect(try await store.credential(providerIdentifier: "openai") == "sk-first")

        try await store.save("sk-replacement", providerIdentifier: "openai")
        #expect(try await store.credential(providerIdentifier: "openai") == "sk-replacement")

        try await store.delete(providerIdentifier: "openai")
        #expect(try await store.contains(providerIdentifier: "openai") == false)
        #expect(await backend.allValues().isEmpty)
    }

    @Test(arguments: ["", "   ", "bad provider", "provider/../../key", "🔑"])
    func rejectsUnsafeProviderIdentifiers(value: String) async {
        let store = ProviderCredentialStore(backend: InMemoryCredentialBackend())
        await #expect(throws: ProviderCredentialError.self) {
            try await store.save("secret", providerIdentifier: value)
        }
    }

    @Test func rejectsEmptyAndOversizedCredentials() async {
        let store = ProviderCredentialStore(backend: InMemoryCredentialBackend())
        await #expect(throws: ProviderCredentialError.self) {
            try await store.save("  ", providerIdentifier: "openai")
        }
        await #expect(throws: ProviderCredentialError.self) {
            try await store.save(String(repeating: "x", count: 8_193), providerIdentifier: "openai")
        }
    }
}

private actor InMemoryCredentialBackend: ProviderCredentialBackend {
    private var values: [String: Data] = [:]

    func read(account: String) async throws -> Data? { values[account] }
    func write(_ data: Data, account: String) async throws { values[account] = data }
    func delete(account: String) async throws { values[account] = nil }
    func allValues() -> [String: Data] { values }
}
