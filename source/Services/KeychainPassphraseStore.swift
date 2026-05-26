import Foundation
import OSLog
import Security

private let keychainLog = Logger(
    subsystem: "com.peakinnovationstudios.GPGManager",
    category: "keychain"
)

/// Read/write store for GPG passphrases in the macOS Keychain. Items are stored
/// under service "GnuPG" with the keygrip as the account, matching pinentry-mac's
/// convention so account identifiers remain interoperable.
///
/// New entries live in our shared `keychain-access-groups` group, which both the
/// main app and the embedded pinentry helper declare. This is required to use
/// `kSecAttrAccessControl = .userPresence` (Touch ID): without the entitlement,
/// SecItemAdd returns `errSecMissingEntitlement` (-34018). The access group
/// also gives both binaries silent reads of each other's entries — no macOS
/// "wants to use keychain" dialog.
///
/// Legacy entries created by pinentry-mac (no access group) are still readable
/// — `readPassphrase` and `migrateToBiometric` look in the default group as a
/// fallback. On first migration, the legacy entry is read, deleted, and rewritten
/// into our access group with userPresence.
struct KeychainPassphraseStore {
    let service: String

    /// The keychain-access-group both targets declare in their entitlements.
    /// At sign time `$(AppIdentifierPrefix)` is replaced by the team prefix
    /// (`Z2R2L2TJ7Y.`), making the runtime value match what's embedded.
    static let accessGroup = "Z2R2L2TJ7Y.com.peakinnovationstudios.GPGManager"

    init(service: String = "GnuPG") {
        self.service = service
    }

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

    func readPassphrase(account: String) -> String? {
        if let value = readInGroup(account: account, accessGroup: Self.accessGroup) {
            return value
        }
        return readInGroup(account: account, accessGroup: nil)
    }

    private func readInGroup(account: String, accessGroup: String?) -> String? {
        var query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the entry from both our access group AND the default group, so
    /// "delete" semantically removes the secret regardless of where it lives.
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

    @discardableResult
    func savePassphrase(_ passphrase: String, account: String, label: String? = nil) -> Bool {
        switch save(passphrase, account: account, label: label) {
        case .userPresence, .withoutBiometric: return true
        case .failed: return false
        }
    }

    enum SaveOutcome {
        case userPresence              // Touch ID-protected
        case withoutBiometric          // Fallback save without userPresence
        case failed(status: OSStatus, path: String)
    }

    private func save(_ passphrase: String, account: String, label: String? = nil) -> SaveOutcome {
        guard let data = passphrase.data(using: .utf8) else {
            keychainLog.error("Passphrase data encoding failed for \(account, privacy: .public)")
            return .failed(status: errSecParam, path: "encode")
        }
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        ) else {
            keychainLog.error("SecAccessControlCreateWithFlags returned nil")
            return .failed(status: errSecParam, path: "access-control")
        }

        let effectiveLabel = (label?.isEmpty == false) ? label! : account

        // Delete any prior copies (in both groups) before adding. SecItemUpdate
        // can't modify kSecAttrAccessControl on an existing item per Apple's
        // docs, so a fresh add is the only reliable way to apply userPresence.
        deletePassphrase(account: account)

        // Don't set kSecAttrAccessGroup on userPresence-protected items —
        // the combination causes SecItemAdd to return errSecSuccess while
        // silently failing to persist the item. The keychain-access-groups
        // entitlement implicitly puts items into the first declared group
        // (our shared group) when no group is specified explicitly.
        let addAttrs: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        service,
            kSecAttrAccount:        account,
            kSecAttrLabel:          effectiveLabel,
            kSecValueData:          data,
            kSecAttrAccessControl:  access
        ]
        let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
        if addStatus == errSecSuccess {
            // Verify by reading back immediately. If the item isn't findable,
            // we silently failed to persist (a known interaction between
            // kSecAttrAccessControl and other attrs).
            if existsInGroup(account: account, accessGroup: nil) {
                keychainLog.info("Added userPresence entry for \(account, privacy: .public)")
                return .userPresence
            }
            keychainLog.error("userPresence SecItemAdd phantom-success for \(account, privacy: .public)")
        }
        keychainLog.notice("userPresence SecItemAdd status=\(addStatus) account=\(account, privacy: .public)")

        // Non-biometric fallback (shouldn't be needed once entitlements are
        // wired, but kept so a missing entitlement doesn't silently lose data).
        let recoveryAttrs: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     account,
            kSecAttrLabel:       effectiveLabel,
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrAccessGroup: Self.accessGroup
        ]
        let recoveryStatus = SecItemAdd(recoveryAttrs as CFDictionary, nil)
        if recoveryStatus == errSecSuccess {
            keychainLog.info("Recovery (non-biometric) add succeeded for \(account, privacy: .public)")
            return .withoutBiometric
        }
        keychainLog.error("Recovery add status=\(recoveryStatus) account=\(account, privacy: .public)")
        return .failed(status: addStatus, path: "add")
    }

    enum MigrationResult {
        case migrated                  // Saved with userPresence (Touch ID)
        case savedWithoutBiometric     // Saved but Touch ID couldn't be enabled
        case noExistingEntry
        case readDenied
        case saveFailed(status: OSStatus, path: String)

        var diagnostic: String {
            if case .saveFailed(let status, let path) = self {
                let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
                return "\(path) failed: \(message) (\(status))"
            }
            return ""
        }
    }

    func migrateToBiometric(account: String) -> MigrationResult {
        guard exists(account: account) else { return .noExistingEntry }
        guard let passphrase = readPassphrase(account: account) else { return .readDenied }
        switch save(passphrase, account: account) {
        case .userPresence:          return .migrated
        case .withoutBiometric:      return .savedWithoutBiometric
        case .failed(let status, let path): return .saveFailed(status: status, path: path)
        }
    }
}
