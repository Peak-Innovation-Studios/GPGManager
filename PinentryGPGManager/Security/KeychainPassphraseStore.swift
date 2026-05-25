import Foundation
import LocalAuthentication
import OSLog
import Security

private let keychainLog = Logger(
    subsystem: "com.peakinnovationstudios.PinentryGPGManager",
    category: "keychain"
)

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

    /// Saves a passphrase to the Keychain. Prefers Touch ID protection
    /// (`.userPresence`); if that fails — common in ad-hoc-signed dev builds —
    /// falls back to a non-biometric entry so the data is at least preserved.
    /// Operational outcomes are logged via `os.Logger`; filter Console.app on
    /// subsystem `com.peakinnovationstudios.PinentryGPGManager`.
    @discardableResult
    func savePassphrase(_ passphrase: String, account: String, label: String? = nil) -> Bool {
        guard let data = passphrase.data(using: .utf8) else {
            keychainLog.error("Passphrase data encoding failed")
            return false
        }

        let effectiveLabel = (label?.isEmpty == false) ? label! : account

        let lookup: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        var updateAttrs: [CFString: Any] = [kSecValueData: data]
        updateAttrs[kSecAttrLabel] = effectiveLabel
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            updateAttrs as CFDictionary
        )
        if updateStatus == errSecSuccess {
            keychainLog.info("Updated existing entry for \(account, privacy: .public)")
            return true
        }
        if updateStatus != errSecItemNotFound {
            keychainLog.error("SecItemUpdate failed status=\(updateStatus) account=\(account, privacy: .public)")
            return false
        }

        // No existing entry — try Touch ID-protected add.
        if let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        ) {
            let attrs: [CFString: Any] = [
                kSecClass:              kSecClassGenericPassword,
                kSecAttrService:        service,
                kSecAttrAccount:        account,
                kSecAttrLabel:          effectiveLabel,
                kSecValueData:          data,
                kSecAttrAccessControl:  access
            ]
            let addStatus = SecItemAdd(attrs as CFDictionary, nil)
            if addStatus == errSecSuccess {
                keychainLog.info("Added Touch ID-protected entry for \(account, privacy: .public)")
                return true
            }
            keychainLog.notice("userPresence add failed status=\(addStatus) account=\(account, privacy: .public) — falling back")
        } else {
            keychainLog.notice("SecAccessControlCreateWithFlags returned nil — falling back")
        }

        // Fall back to a normal (non-biometric) Keychain entry so the
        // passphrase isn't lost. The user can manually upgrade later.
        let fallbackAttrs: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    service,
            kSecAttrAccount:    account,
            kSecAttrLabel:      effectiveLabel,
            kSecValueData:      data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let fallbackStatus = SecItemAdd(fallbackAttrs as CFDictionary, nil)
        if fallbackStatus == errSecSuccess {
            keychainLog.info("Added fallback (non-biometric) entry for \(account, privacy: .public)")
            return true
        }
        keychainLog.error("Fallback add also failed status=\(fallbackStatus) account=\(account, privacy: .public)")
        return false
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
