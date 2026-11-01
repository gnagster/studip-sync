import Foundation
import Security

public struct Credentials: Codable, Sendable {
    public var username: String
    public var password: String
    public init(username: String, password: String) { self.username = username; self.password = password }
}

public enum CredentialVault {
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.gnagster.StudSync",
        kSecAttrAccount as String: "goettingen"
    ] }
    public static func read() throws -> Credentials? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw vaultError(status) }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }
    public static func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let values = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw vaultError(added) }
        } else if status != errSecSuccess { throw vaultError(status) }
    }
    public static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw vaultError(status) }
    }
    private static func vaultError(_ code: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "StudSync could not access its Keychain credentials (\(code))."])
    }
}
