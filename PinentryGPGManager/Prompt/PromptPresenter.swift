import AppKit
import SwiftUI

enum PromptPresenter {
    static func presentPassphrase(_ request: PinentryRequest) -> PromptOutcome {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: PromptOutcome = .cancelled

        DispatchQueue.main.async {
            let host = PromptWindowHost()
            host.show(title: request.effectiveTitle) { close in
                PassphraseView(
                    request: request,
                    onSubmit: { passphrase, saveToKeychain in
                        outcome = .submitted(passphrase: passphrase, saveToKeychain: saveToKeychain)
                        close()
                    },
                    onCancel: {
                        outcome = .cancelled
                        close()
                    }
                )
            } onClose: {
                semaphore.signal()
            }
        }

        semaphore.wait()
        return outcome
    }

    static func presentConfirm(_ request: PinentryRequest, oneButton: Bool) -> PromptOutcome {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: PromptOutcome = oneButton ? .confirmed : .cancelled

        DispatchQueue.main.async {
            let host = PromptWindowHost()
            host.show(title: request.effectiveTitle) { close in
                ConfirmView(
                    request: request,
                    oneButton: oneButton,
                    onConfirm: {
                        outcome = .confirmed
                        close()
                    },
                    onDecline: {
                        outcome = .declined
                        close()
                    },
                    onCancel: {
                        outcome = .cancelled
                        close()
                    }
                )
            } onClose: {
                semaphore.signal()
            }
        }

        semaphore.wait()
        return outcome
    }
}
