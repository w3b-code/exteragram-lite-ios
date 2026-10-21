import Foundation
#if canImport(Security)
import Security
#endif

public enum ExteraMicrosoftCredentialStoreError: Error, Equatable, Sendable {
    case invalidConfiguration
    case corruptData
    case unavailable
    case keychainFailure(Int32)
}

extension ExteraMicrosoftCredentialStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Check the Azure Translator subscription key and region."
        case .corruptData: return "The saved Microsoft configuration could not be read. Configure it again."
        case .unavailable: return "Secure credential storage is unavailable on this platform."
        case .keychainFailure: return "The Microsoft credential could not be accessed in the device keychain."
        }
    }
}

/// App-local credentials for the user's own Azure resource. Call synchronous
/// Keychain operations from a background executor. No access group, cloud sync,
/// UserDefaults, file export, developer key, or logging is involved.
public enum ExteraMicrosoftCredentialStore {
    static func normalized(_ value: ExteraMicrosoftCredentials) throws -> ExteraMicrosoftCredentials {
        let key = value.subscriptionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 512, key.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else {
            throw ExteraMicrosoftCredentialStoreError.invalidConfiguration
        }
        let region = value.region?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let region, !region.isEmpty {
            guard region.utf8.count <= 64, region.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil else {
                throw ExteraMicrosoftCredentialStoreError.invalidConfiguration
            }
        }
        return ExteraMicrosoftCredentials(subscriptionKey: key, region: region?.isEmpty == false ? region : nil)
    }

    static func encoded(_ value: ExteraMicrosoftCredentials) throws -> Data {
        try JSONEncoder().encode(normalized(value))
    }

    static func decoded(_ data: Data) throws -> ExteraMicrosoftCredentials {
        guard data.count <= 4096 else { throw ExteraMicrosoftCredentialStoreError.corruptData }
        do { return try normalized(JSONDecoder().decode(ExteraMicrosoftCredentials.self, from: data)) }
        catch { throw ExteraMicrosoftCredentialStoreError.corruptData }
    }

    #if canImport(Security)
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.exteragram.lite.translation.microsoft",
         kSecAttrAccount as String: "azure-resource",
         kSecAttrSynchronizable as String: false]
    }
    #endif

    public static func load() throws -> ExteraMicrosoftCredentials? {
        #if canImport(Security)
        var match = query
        match[kSecReturnData as String] = true
        match[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(match as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ExteraMicrosoftCredentialStoreError.keychainFailure(status) }
        guard let data = value as? Data else { throw ExteraMicrosoftCredentialStoreError.corruptData }
        return try decoded(data)
        #else
        throw ExteraMicrosoftCredentialStoreError.unavailable
        #endif
    }

    public static func save(_ value: ExteraMicrosoftCredentials) throws {
        let data = try encoded(value)
        #if canImport(Security)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addition = query.merging(attributes) { _, new in new }
            status = SecItemAdd(addition as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary) }
        }
        guard status == errSecSuccess else { throw ExteraMicrosoftCredentialStoreError.keychainFailure(status) }
        #else
        _ = data
        throw ExteraMicrosoftCredentialStoreError.unavailable
        #endif
    }

    public static func delete() throws {
        #if canImport(Security)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ExteraMicrosoftCredentialStoreError.keychainFailure(status)
        }
        #else
        throw ExteraMicrosoftCredentialStoreError.unavailable
        #endif
    }
}
