import Foundation
import Security

enum KeychainStoreError: Error {
    case unexpectedStatus(OSStatus)
}

protocol APIKeyStoring {
    func saveAPIKey(_ key: String) throws
    func readAPIKey() throws -> String?
    func removeAPIKey() throws
}

struct KeychainStore: APIKeyStoring {
    private let service = "com.rafi.Reflex.openrouter"
    private let account = "api-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query = baseQuery
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }
    }

    func readAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        return key
    }

    func removeAPIKey() throws {
        let query = baseQuery
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}

struct DisabledKeychainStore: APIKeyStoring {
    func saveAPIKey(_ key: String) throws {}
    func readAPIKey() throws -> String? { nil }
    func removeAPIKey() throws {}
}
