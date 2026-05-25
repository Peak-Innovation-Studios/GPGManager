import Foundation
import OSLog
import Security

private let keychainLog = Logger(
    subsystem: "com.peakinnovationstudios.GPGManager",
    category: "keychain"
)

/// Read/write store for GPG passphrases in the macOS Keychain. Items are stored
/// under service "GnuPG" with the keygrip as the account, matching pinentry-mac's
/// convention — so entries created by GPG Suite are interoperable.
///
/// Reads from this store may trigger a macOS "Allow" prompt for ACL-protected
/// entries (e.g. existing pinentry-mac entries) or a Touch ID prompt for entries
/// migrated via `migrateToBiometric(account:)`.
struct KeychainPassphraseStore {
    let service: String

    init(service: String = "GnuPG") {
        self.service = service
    }

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

    func readPassphrase(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves with `.userPresence` access control. If an entry already exists we
    /// first try an in-place SecItemUpdate (which preserves the keychain item's
    /// identity), and fall back to delete + add when that's not supported.
    func deletePassphrase(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
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

        let lookup: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let updateAttrs: [CFString: Any] = [
            kSecValueData:         data,
            kSecAttrAccessControl: access,
            kSecAttrLabel:         effectiveLabel
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess {
            keychainLog.info("In-place update to userPresence succeeded for \(account, privacy: .public)")
            return .userPresence
        }
        keychainLog.notice("SecItemUpdate status=\(updateStatus) account=\(account, privacy: .public)")

        if updateStatus != errSecItemNotFound {
            let deleteStatus = SecItemDelete(lookup as CFDictionary)
            keychainLog.notice("SecItemDelete status=\(deleteStatus) account=\(account, privacy: .public)")
            if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
                return .failed(status: deleteStatus, path: "delete")
            }
        }

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
            keychainLog.info("Added userPresence entry for \(account, privacy: .public)")
            return .userPresence
        }
        keychainLog.notice("userPresence SecItemAdd status=\(addStatus) account=\(account, privacy: .public)")

        let recoveryAttrs: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    service,
            kSecAttrAccount:    account,
            kSecAttrLabel:      effectiveLabel,
            kSecValueData:      data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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
