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
}

enum PromptOutcome {
    case submitted(passphrase: String, saveToKeychain: Bool)
    case cancelled
    case confirmed
    case declined
}
