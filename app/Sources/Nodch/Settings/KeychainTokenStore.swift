import Foundation
import NodchCore
import Security

/// The Nod token in the login Keychain: a generic password, service `dev.nodch.Nodch`, account the server's origin.
/// The token is never logged; errors carry only the Keychain's status.
@MainActor final class KeychainTokenStore: TokenStore {
    static let service = "dev.nodch.Nodch"

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let detail = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "OSStatus \(status)"
            return "The Keychain didn’t store the token: \(detail)"
        }
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: account]
    }

    func token(account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setToken(_ token: String, account: String) throws {
        let data = Data(token.utf8)
        let updated = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw Failure(status: updated) }
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "nodch: Nod token (\(account))"
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure(status: added) }
    }

    func removeToken(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
