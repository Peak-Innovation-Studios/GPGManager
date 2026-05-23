import AppKit
import Foundation

final class PinentryController: AssuanHandler {
    private let lock = NSLock()
    private var request = PinentryRequest()
    private let keychain = KeychainPassphraseStore()

    func handle(_ command: AssuanCommand) -> AssuanCommandResult {
        switch command {
        case .bye:
            return .bye

        case .setDesc(let value):    mutate { $0.description = value };       return .ok(message: nil)
        case .setPrompt(let value):  mutate { $0.prompt = value };             return .ok(message: nil)
        case .setKeyInfo(let value): mutate { $0.keyInfo = value };            return .ok(message: nil)
        case .setTitle(let value):   mutate { $0.title = value };              return .ok(message: nil)
        case .setOK(let value):      mutate { $0.okLabel = value };            return .ok(message: nil)
        case .setCancel(let value):  mutate { $0.cancelLabel = value };        return .ok(message: nil)
        case .setNotOK(let value):   mutate { $0.notOkLabel = value };         return .ok(message: nil)
        case .setError(let value):   mutate { $0.errorMessage = value };       return .ok(message: nil)

        case .setRepeat(let label):
            mutate { $0.repeatPrompt = label ?? "" }
            return .ok(message: nil)

        case .setRepeatError(let value):
            mutate { $0.repeatError = value }
            return .ok(message: nil)

        case .setQualityBar(let label):
            mutate { $0.qualityBarLabel = label ?? "" }
            return .ok(message: nil)

        case .setQualityBarTooltip(let value):
            mutate { $0.qualityBarTooltip = value }
            return .ok(message: nil)

        case .reset:
            mutate { $0 = PinentryRequest() }
            return .ok(message: nil)

        case .getPin:
            return promptForPassphrase()

        case .confirm(let oneButton):
            return promptForConfirmation(oneButton: oneButton)

        case .message:
            return promptForMessage()

        case .getInfo(let what):
            switch what.lowercased() {
            case "pid":     return .data(String(ProcessInfo.processInfo.processIdentifier))
            case "version": return .data("1.0")
            case "flavor":  return .data("gpgmanager")
            default:        return .error(code: AssuanErrorCode.notImplemented, description: "Unknown GETINFO \(what)")
            }

        case .nop, .option:
            return .ok(message: nil)

        case .unknown(let verb, _):
            return .error(code: AssuanErrorCode.unknownCommand, description: "Unknown command \(verb)")
        }
    }

    private func mutate(_ change: (inout PinentryRequest) -> Void) {
        lock.lock()
        change(&request)
        lock.unlock()
    }

    private func snapshot() -> PinentryRequest {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    private func consumeRequestAfterPrompt() {
        mutate {
            $0.errorMessage = nil
            $0.repeatPrompt = nil
            $0.repeatError = nil
            $0.qualityBarLabel = nil
            $0.qualityBarTooltip = nil
            $0.allowKeychainSave = false
        }
    }

    private func promptForPassphrase() -> AssuanCommandResult {
        var snapshot = self.snapshot()

        // Touch ID fast-path: if the agent provided a keygrip and we have a
        // matching Keychain entry, prompt for biometrics and skip the dialog.
        if !snapshot.requiresConfirmation,
           let keygrip = snapshot.keygrip,
           keychain.exists(account: keygrip) {
            let reason = biometricReason(for: snapshot)
            if let storedPassphrase = keychain.readPassphrase(account: keygrip, reason: reason) {
                consumeRequestAfterPrompt()
                return .data(storedPassphrase)
            }
        }

        // Offer "Save in Keychain" only on new-passphrase prompts or when we
        // have a keygrip to associate the entry with.
        if snapshot.keygrip != nil {
            mutate { $0.allowKeychainSave = true }
            snapshot.allowKeychainSave = true
        }

        let outcome = PromptPresenter.presentPassphrase(snapshot)
        consumeRequestAfterPrompt()

        switch outcome {
        case .submitted(let passphrase, let saveToKeychain):
            if saveToKeychain, let keygrip = snapshot.keygrip {
                keychain.savePassphrase(passphrase, account: keygrip)
            }
            return .data(passphrase)
        case .cancelled, .confirmed, .declined:
            return .error(code: AssuanErrorCode.canceled, description: "Operation cancelled")
        }
    }

    private func biometricReason(for snapshot: PinentryRequest) -> String {
        if let description = snapshot.description, !description.isEmpty {
            return description
        }
        return "Unlock your GPG passphrase"
    }

    private func promptForConfirmation(oneButton: Bool) -> AssuanCommandResult {
        let snapshot = self.snapshot()
        let outcome = PromptPresenter.presentConfirm(snapshot, oneButton: oneButton)
        consumeRequestAfterPrompt()

        switch outcome {
        case .confirmed:
            return .ok(message: nil)
        case .declined:
            return .error(code: AssuanErrorCode.notConfirmed, description: "Not confirmed")
        case .cancelled, .submitted:
            return .error(code: AssuanErrorCode.canceled, description: "Operation cancelled")
        }
    }

    private func promptForMessage() -> AssuanCommandResult {
        let snapshot = self.snapshot()
        _ = PromptPresenter.presentConfirm(snapshot, oneButton: true)
        consumeRequestAfterPrompt()
        return .ok(message: nil)
    }
}
