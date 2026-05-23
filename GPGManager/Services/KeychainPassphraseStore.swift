import Foundation
import Security

// NOTE: This is the write-side counterpart to the helper's KeychainPassphraseStore
// (which handles reads with Touch ID). Items are stored under service "GnuPG"
// with the keygrip as the account, matching pinentry-mac's convention.

struct KeychainPassphraseStore {
    let service: String

    init(service: String = "GnuPG") {
        self.service = service
    }

    @discardableResult
    func savePassphrase(_ passphrase: String, account: String) -> Bool {
        guard let data = passphrase.data(using: .utf8) else { return false }

        let lookup: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        ) else { return false }

        let attrs: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        service,
            kSecAttrAccount:        account,
            kSecValueData:          data,
            kSecAttrAccessControl:  access
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }
}
