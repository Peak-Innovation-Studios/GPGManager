import Foundation

struct PinentryRequest: Equatable {
    var title: String?
    var description: String?
    var prompt: String?
    var keyInfo: String?
    var okLabel: String?
    var cancelLabel: String?
    var notOkLabel: String?
    var errorMessage: String?
    var repeatPrompt: String?
    var repeatError: String?
    var qualityBarLabel: String?
    var qualityBarTooltip: String?
    var allowKeychainSave: Bool = false

    var requiresConfirmation: Bool {
        repeatPrompt != nil
    }

    var showsQualityBar: Bool {
        qualityBarLabel != nil
    }

    /// Extracted from SETKEYINFO (e.g., `n/ABC123…` → `ABC123…`).
    /// Matches the account name pinentry-mac uses for Keychain items.
    var keygrip: String? {
        guard let info = keyInfo, !info.isEmpty else { return nil }
        if let slash = info.firstIndex(of: "/") {
            let value = String(info[info.index(after: slash)...])
            return value.isEmpty ? nil : value
        }
        return info
    }

    var effectiveTitle: String {
        if let title, !title.isEmpty { return title }
        return "GPG Manager Passphrase"
    }

    var effectivePrompt: String {
        if let prompt, !prompt.isEmpty { return prompt }
        return "Passphrase"
    }

    var effectiveOK: String {
        if let okLabel, !okLabel.isEmpty { return okLabel }
        // gpg-agent often skips SETOK and lets pinentry pick. Default to the
        // action verb implied by the title — reads with more intent than "OK".
        let lowerTitle = effectiveTitle.lowercased()
        if lowerTitle.contains("unlock")  { return "Unlock" }
        if lowerTitle.contains("create")  { return "Create" }
        if lowerTitle.contains("confirm") { return "Confirm" }
        return "OK"
    }

    var effectiveCancel: String {
        if let cancelLabel, !cancelLabel.isEmpty { return cancelLabel }
        return "Cancel"
    }

    var effectiveRepeatPrompt: String {
        if let repeatPrompt, !repeatPrompt.isEmpty { return repeatPrompt }
        return "Confirm passphrase"
    }

    /// Derives a friendly Keychain label from gpg-agent's SETDESC text.
    /// The description includes a quoted `"Name <email>"` plus a `key ID <HEX>`
    /// line — pinentry-mac uses `"<uid> (<keyID>)"` as the label and we match
    /// that so entries look the same in Keychain Access.
    var keychainLabel: String? {
        guard let description else { return nil }

        let uid: String?
        if let uidRange = description.range(of: #""[^"]+<[^>]+@[^>]+>""#, options: .regularExpression) {
            uid = String(description[uidRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        } else {
            uid = nil
        }

        let keyID: String?
        if let idRange = description.range(of: #"ID\s+([0-9A-Fa-f]{16})"#, options: .regularExpression) {
            let chunk = String(description[idRange])
            keyID = chunk.split(whereSeparator: { !$0.isHexDigit }).last.map(String.init)
        } else {
            keyID = nil
        }

        switch (uid, keyID) {
        case let (uid?, keyID?): return "\(uid) (\(keyID))"
        case let (uid?, nil):    return uid
        case let (nil, keyID?):  return keyID
        case (nil, nil):         return nil
        }
    }
}

enum PromptOutcome {
    case submitted(passphrase: String, saveToKeychain: Bool)
    case cancelled
    case confirmed
    case declined
}
