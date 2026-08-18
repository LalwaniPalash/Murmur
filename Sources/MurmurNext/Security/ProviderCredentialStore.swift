import Foundation
import Security

enum ProviderCredentialError: Error, Equatable, LocalizedError, Sendable {
    case invalidProviderIdentifier
    case invalidCredential
    case unavailable
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidProviderIdentifier: "The provider identifier is invalid."
        case .invalidCredential: "Enter a valid provider key."
        case .unavailable: "No provider key is stored."
        case .keychain: "Murmur could not access the provider key in Keychain."
        }
    }
}

protocol ProviderCredentialProviding: Sendable {
    func credential(providerIdentifier: String) async throws -> String
}

protocol ProviderCredentialBackend: Sendable {
    func read(account: String) async throws -> Data?
    func write(_ data: Data, account: String) async throws
    func delete(account: String) async throws
}

actor ProviderCredentialStore: ProviderCredentialProviding {
    static let shared = ProviderCredentialStore(backend: SecurityProviderCredentialBackend())

    private let backend: any ProviderCredentialBackend

    init(backend: any ProviderCredentialBackend) {
        self.backend = backend
    }

    func save(_ credential: String, providerIdentifier: String) async throws {
        let account = try account(providerIdentifier)
        let credential = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard credential.isEmpty == false,
              let data = credential.data(using: .utf8),
              data.count <= 8_192
        else { throw ProviderCredentialError.invalidCredential }
        try await backend.write(data, account: account)
    }

    func contains(providerIdentifier: String) async throws -> Bool {
        try await backend.read(account: account(providerIdentifier)) != nil
    }

    func delete(providerIdentifier: String) async throws {
        try await backend.delete(account: account(providerIdentifier))
    }

    /// Internal inference boundary only. UI surfaces expose presence, never this value.
    func credential(providerIdentifier: String) async throws -> String {
        guard let data = try await backend.read(account: account(providerIdentifier)),
              let value = String(data: data, encoding: .utf8),
              value.isEmpty == false
        else { throw ProviderCredentialError.unavailable }
        return value
    }

    private func account(_ providerIdentifier: String) throws -> String {
        let range = providerIdentifier.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#, options: .regularExpression)
        guard range?.lowerBound == providerIdentifier.startIndex,
              range?.upperBound == providerIdentifier.endIndex
        else { throw ProviderCredentialError.invalidProviderIdentifier }
        return providerIdentifier
    }
}

private struct SecurityProviderCredentialBackend: ProviderCredentialBackend {
    private let service = "app.murmur.provider-credentials"

    func read(account: String) async throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ProviderCredentialError.keychain(status)
        }
        return data
    }

    func write(_ data: Data, account: String) async throws {
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ProviderCredentialError.keychain(updateStatus)
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw ProviderCredentialError.keychain(addStatus) }
    }

    func delete(account: String) async throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderCredentialError.keychain(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
