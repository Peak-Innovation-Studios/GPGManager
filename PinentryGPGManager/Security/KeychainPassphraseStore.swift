import Foundation
import LocalAuthentication
import OSLog
import Security

private let keychainLog = Logger(
    subsystem: "com.peakinnovationstudios.PinentryGPGManager",
    category: "keychain"
)

/// Reads and writes GPG passphrases from the macOS Keychain.
///
/// Items live in the shared `keychain-access-groups` group both targets declare
/// in their entitlements — required to use `kSecAttrAccessControl = .userPresence`
/// (Touch ID), and also gives the main app silent reads of items the helper
/// wrote (no macOS "wants to use keychain" dialog). Legacy entries created by
/// pinentry-mac (no access group) are read from the default group as a fallback
/// and migrated on the next write.
struct KeychainPassphraseStore {
    let service: String

    /// Matches `$(AppIdentifierPrefix)com.peakinnovationstudios.GPGManager`
    /// declared in PinentryGPGManager.entitlements.
    static let accessGroup = "Z2R2L2TJ7Y.com.peakinnovationstudios.GPGManager"

    init(service: String = "GnuPG") {
        self.service = service
    }

    /// Reads a passphrase, prompting Touch ID / passcode if the item requires it.
    /// Returns nil if the item doesn't exist or the user cancels. Tries our
    /// access group first, then falls back to the default (legacy pinentry-mac)
    /// group so existing entries remain readable.
    func readPassphrase(account: String, reason: String) -> String? {
        if let value = readInGroup(account: account, accessGroup: Self.accessGroup, reason: reason) {
            return value
        }
        return readInGroup(account: account, accessGroup: nil, reason: reason)
    }

    private func readInGroup(account: String, accessGroup: String?, reason: String) -> String? {
        let context = LAContext()
        context.localizedReason = reason

        var query: [CFString: Any] = [
            kSecClass:                  kSecClassGenericPassword,
            kSecAttrService:            service,
            kSecAttrAccount:            account,
            kSecReturnData:             true,
            kSecMatchLimit:             kSecMatchLimitOne,
            kSecUseAuthenticationContext: context
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Returns true if an item exists for this account, without triggering auth.
    /// Checks both our access group and the default group.
    func exists(account: String) -> Bool {
        return existsInGroup(account: account, accessGroup: Self.accessGroup)
            || existsInGroup(account: account, accessGroup: nil)
    }

    private func existsInGroup(account: String, accessGroup: String?) -> Bool {
        var query: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrService:         service,
            kSecAttrAccount:         account,
            kSecMatchLimit:          kSecMatchLimitOne,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Saves a passphrase to the Keychain. Prefers Touch ID protection
    /// (`.userPresence`); if that fails — e.g. ad-hoc-signed dev builds without
    /// keychain-access-groups entitlement — falls back to a non-biometric entry
    /// so the data is at least preserved. Operational outcomes are logged via
    /// `os.Logger`; filter Console.app on subsystem
    /// `com.peakinnovationstudios.PinentryGPGManager`.
    @discardableResult
    func savePassphrase(_ passphrase: String, account: String, label: String? = nil) -> Bool {
        guard let data = passphrase.data(using: .utf8) else {
            keychainLog.error("Passphrase data encoding failed")
            return false
        }

        let effectiveLabel = (label?.isEmpty == false) ? label! : account

        // Delete any prior copies before adding. SecItemUpdate can't modify
        // kSecAttrAccessControl on an existing item, so a fresh add is the
        // only reliable way to apply userPresence. Delete from both groups so
        // we don't end up with stale copies in the default group.
        deletePassphrase(account: account)

        // Touch ID-protected add.
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
                kSecAttrAccessControl:  access,
                kSecAttrAccessGroup:    Self.accessGroup
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

        // Non-biometric fallback so the passphrase isn't lost. The user can
        // re-trigger biometric upgrade later from the main app.
        let fallbackAttrs: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     account,
            kSecAttrLabel:       effectiveLabel,
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrAccessGroup: Self.accessGroup
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
        let baseQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        var ours = baseQuery
        ours[kSecAttrAccessGroup] = Self.accessGroup
        SecItemDelete(ours as CFDictionary)
        SecItemDelete(baseQuery as CFDictionary)
    }
}
