import SwiftUI

struct MyKeysPanel: View {
    @Environment(GPGAppState.self) private var state

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if state.secretKeys.isEmpty {
                    EmptyKeysState()
                } else {
                    ForEach(state.secretKeys) { key in
                        SecretKeyCard(key: key)
                        if key.id != state.secretKeys.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(8)
        } label: {
            Label("My Keys", systemImage: "key.fill")
                .labelStyle(.largeIcon)
        }
    }
}

private struct EmptyKeysState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No secret keys yet.")
                .font(.headline)
            Text("Click New Key in the toolbar to generate your first OpenPGP key pair.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

private struct SecretKeyCard: View {
    @Environment(GPGAppState.self) private var state
    @State private var showingDetails = false
    @State private var showingEditUID = false
    @State private var showingRevealPassphrase = false
    @State private var confirmingDelete = false
    let key: GPGKey

    private var isDefault: Bool {
        guard let defaultKey = state.gpgConfig.defaultKey, !defaultKey.isEmpty else { return false }
        return key.keyID == defaultKey || key.fingerprint == defaultKey
    }

    private var isExpired: Bool {
        guard let expires = key.expiresAt else { return false }
        return expires < Date()
    }

    private var isExpiringSoon: Bool {
        guard !isExpired, let expires = key.expiresAt else { return false }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0
        return days < 30
    }

    private var registeredOnGitHub: GitHubRegisteredKey? {
        state.gitHubKeyCheck.registeredKeys.first { $0.matches(keyID: key.keyID) }
    }

    private var isNotOnGitHub: Bool {
        guard isDefault, state.gitHubKeyCheck.isLoaded else { return false }
        return registeredOnGitHub == nil
    }

    /// GitHub considers the key expired but the local copy is still valid.
    /// Different expiry dates that both still consider the key valid (e.g.
    /// future date vs nil) aren't worth flagging — they don't break anything.
    private var isStaleOnGitHub: Bool {
        guard let registered = registeredOnGitHub else { return false }
        return registered.isExpired && !isExpired
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isExpired ? "key.slash.fill" : "key.fill")
                .font(.system(size: 28))
                .foregroundStyle(isExpired ? Color.secondary : Color.accentColor)
                .frame(width: 36, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(key.primaryUserID)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    badges
                }

                Text(key.shortFingerprint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text(expirySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    if !isDefault {
                        Button("Set as Default", systemImage: "star") {
                            state.setDefaultKey(key)
                        }
                        .controlSize(.small)
                    }
                    Button("Edit User ID", systemImage: "person.text.rectangle") {
                        showingEditUID = true
                    }
                    .controlSize(.small)
                    if !state.hasKeychainEntry(for: key) {
                        Button("Enable Touch ID", systemImage: "touchid") {
                            Task { await state.enableTouchID(for: key) }
                        }
                        .controlSize(.small)
                        .help("Imports an existing GPG Suite Keychain entry and protects it with Touch ID")
                    }
                    Button("Copy Public Key", systemImage: "doc.on.doc") {
                        Task { await state.copyPublicKeyToPasteboard(key) }
                    }
                    .controlSize(.small)
                    if state.gitHubKeyCheck.isLoaded, registeredOnGitHub == nil {
                        Button("Add to GitHub", systemImage: "arrow.up.circle") {
                            Task { await state.uploadKeyToGitHub(key) }
                        }
                        .controlSize(.small)
                    }
                    Menu {
                        if state.hasKeychainEntry(for: key) {
                            Button("Reveal Passphrase…", systemImage: "eye") {
                                showingRevealPassphrase = true
                            }
                            Divider()
                        }
                        Button("Delete Key…", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More actions")
                }
                .padding(.top, 2)
            }

            Spacer()

            Button {
                showingDetails.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Show key details")
            .popover(isPresented: $showingDetails, arrowEdge: .trailing) {
                KeyDetailsPopover(key: key)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingEditUID) {
            EditUserIDSheet(key: key)
                .environment(state)
        }
        .sheet(isPresented: $showingRevealPassphrase) {
            RevealPassphraseSheet(key: key)
                .environment(state)
        }
        .confirmationDialog(
            "Delete this key from your local keyring?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Key", role: .destructive) {
                Task { await state.deleteKey(key) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Permanently removes the secret and public halves of \(key.primaryUserID) (and any saved Keychain passphrase). Past commits signed with this key keep their signatures, but you won't be able to sign new ones without a backup.")
        }
    }

    @ViewBuilder
    private var badges: some View {
        if isDefault {
            Badge(text: "DEFAULT", color: .accentColor)
        }
        if isExpired {
            Badge(text: "EXPIRED", color: .red)
        } else if isExpiringSoon {
            Badge(text: "EXPIRING SOON", color: .orange)
        }
        if isNotOnGitHub {
            Badge(text: "NOT ON GITHUB", color: .secondary)
        } else if isStaleOnGitHub {
            Badge(text: "STALE ON GITHUB", color: .orange)
        }
    }

    private var expirySummary: String {
        let created = key.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
        let expires: String
        if let date = key.expiresAt {
            expires = isExpired
                ? "Expired \(date.formatted(date: .abbreviated, time: .omitted))"
                : "Expires \(date.formatted(date: .abbreviated, time: .omitted))"
        } else {
            expires = "Never expires"
        }
        return "\(key.algorithm.displayName) · Created \(created) · \(expires)"
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}

#if DEBUG
#Preview {
    MyKeysPanel()
        .environment(GPGAppState.preview)
        .padding()
        .frame(width: 800)
}
#endif
