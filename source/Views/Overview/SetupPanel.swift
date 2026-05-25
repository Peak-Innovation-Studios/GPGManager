import SwiftUI

struct SetupPanel: View {
    @Environment(GPGAppState.self) private var state

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                SetupRow(check: signingKeyCheck)
                SetupRow(check: passphraseCheck)
                SetupRow(check: gitSigningCheck)
                SetupRow(check: githubCheck)
            }
            .padding(8)
        } label: {
            Label("Setup", systemImage: "checklist")
                .labelStyle(.largeIcon)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var signingKey: GPGKey? {
        GPGKey.match(signingKey: state.gpgConfig.defaultKey, in: state.secretKeys)
    }

    private var signingKeyCheck: SetupCheck {
        guard let key = signingKey else {
            return SetupCheck(status: .error, text: "No default signing key set",
                              detail: "Click Set as Default on a key below.")
        }
        if let expires = key.expiresAt, expires < Date() {
            return SetupCheck(status: .error, text: "Default signing key has expired",
                              detail: key.primaryUserID)
        }
        if let expires = key.expiresAt {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0
            if days < 30 {
                return SetupCheck(status: .warning, text: "Signing key expires in \(days) day\(days == 1 ? "" : "s")",
                                  detail: key.primaryUserID)
            }
        }
        return SetupCheck(status: .ok, text: "Signing with \(key.primaryUserID)")
    }

    private var passphraseCheck: SetupCheck {
        let provider = providerDisplayName(state.passphraseProvider)
        if state.passphraseProvider == .systemDefault {
            return SetupCheck(status: .warning, text: "Passphrase prompt: system default",
                              detail: "GUI signing apps may fail. Choose GPG Manager in Settings → Passphrase.")
        }
        if let ttl = state.agentConfig.defaultCacheTTL, ttl > 0 {
            let summary: String
            if ttl >= 60 {
                let minutes = ttl / 60
                summary = "Cached for \(minutes) min"
            } else {
                summary = "Cached for \(ttl)s"
            }
            return SetupCheck(status: .ok, text: "Passphrase prompt: \(provider)",
                              detail: summary)
        }
        return SetupCheck(status: .ok, text: "Passphrase prompt: \(provider)",
                          detail: "Prompted every time")
    }

    private var gitSigningCheck: SetupCheck {
        let hasKey = !(state.gitSigning.signingKey ?? "").isEmpty
        if hasKey && state.gitSigning.signsCommits {
            return SetupCheck(status: .ok, text: "Git is configured to sign commits")
        }
        if !hasKey {
            return SetupCheck(status: .warning, text: "Git isn't configured for signing",
                              detail: "Set it up in the Signing tab.")
        }
        return SetupCheck(status: .warning, text: "Git has a signing key but signing is off",
                          detail: "Turn on commit signing in the Signing tab.")
    }

    private var githubCheck: SetupCheck {
        guard let key = signingKey else {
            return SetupCheck(status: .neutral, text: "GitHub: pick a default key first")
        }
        switch state.gitHubKeyCheck {
        case .notChecked, .checking:
            return SetupCheck(status: .neutral, text: "GitHub: checking…")
        case .unavailable:
            return SetupCheck(status: .neutral, text: "GitHub status unavailable",
                              detail: "Optional: install gh and run gh auth login.")
        case .scopeRequired:
            return SetupCheck(status: .warning, text: "GitHub needs admin:gpg_key scope",
                              detail: "Visit the Signing tab for the command.")
        case .loaded:
            if state.gitHubKeyCheck.contains(key.keyID) {
                return SetupCheck(status: .ok, text: "Signing key is registered on GitHub")
            }
            return SetupCheck(status: .warning, text: "Signing key not on GitHub",
                              detail: "Add it from the Signing tab.")
        }
    }

    private func providerDisplayName(_ provider: GPGAppState.PassphraseProvider) -> String {
        switch provider {
        case .systemDefault: "system default"
        case .pinentryMac:   "pinentry-mac"
        case .gpgManager:    "GPG Manager"
        case .custom:        "custom helper"
        }
    }
}

struct SetupCheck {
    enum Status { case ok, warning, error, neutral }
    let status: Status
    let text: String
    var detail: String? = nil
}

private struct SetupRow: View {
    let check: SetupCheck

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.body)
                .frame(width: 18, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(check.text)
                if let detail = check.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var iconName: String {
        switch check.status {
        case .ok:      "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error:   "xmark.circle.fill"
        case .neutral: "circle"
        }
    }

    private var iconColor: Color {
        switch check.status {
        case .ok:      .green
        case .warning: .orange
        case .error:   .red
        case .neutral: .secondary
        }
    }
}

#if DEBUG
#Preview {
    SetupPanel()
        .environment(GPGAppState.preview)
        .padding()
        .frame(width: 800)
}
#endif
