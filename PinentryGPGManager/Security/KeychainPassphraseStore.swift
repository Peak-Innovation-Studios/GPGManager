import Foundation
import LocalAuthentication
import Security

/// Reads and writes GPG passphrases from the macOS Keychain.
/// Items are stored as generic passwords under service "GnuPG" with the
/// keygrip as the account, matching pinentry-mac's conventions so existing
/// entries are interoperable.
struct KeychainPassphraseStore {
    let service: String

    init(service: String = "GnuPG") {
        self.service = service
    }

    /// Reads a passphrase, prompting Touch ID / passcode if the item requires it.
    /// Returns nil if the item doesn't exist or the user cancels.
    func readPassphrase(account: String, reason: String) -> String? {
        let context = LAContext()
        context.localizedReason = reason

        let query: [CFString: Any] = [
            kSecClass:                  kSecClassGenericPassword,
            kSecAttrService:            service,
            kSecAttrAccount:            account,
            kSecReturnData:             true,
            kSecMatchLimit:             kSecMatchLimitOne,
            kSecUseAuthenticationContext: context
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Returns true if an item exists for this account, without triggering auth.
    func exists(account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrService:         service,
            kSecAttrAccount:         account,
            kSecMatchLimit:          kSecMatchLimitOne,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Saves a passphrase to the Keychain protected by Touch ID / passcode.
    /// Updates the existing entry in place when present, otherwise creates one.
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

    func deletePassphrase(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
