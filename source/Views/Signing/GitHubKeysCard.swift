import AppKit
import SwiftUI

fileprivate struct PendingKeyAction: Identifiable {
    let id = UUID()
    let remote: GitHubRegisteredKey
    let local: GPGKey
}

struct GitHubKeysCard: View {
    @Environment(GPGAppState.self) private var state
    @State private var pendingDelete: GitHubRegisteredKey?
    @State private var pendingReplace: PendingKeyAction?
    @State private var pendingRefresh: PendingKeyAction?
    @State private var pendingRename: PendingKeyAction?

    private var defaultSecretKey: GPGKey? {
        GPGKey.match(signingKey: state.gpgConfig.defaultKey, in: state.secretKeys)
    }

    private var defaultKeyIsRegistered: Bool {
        guard let key = defaultSecretKey else { return false }
        return state.gitHubKeyCheck.contains(key.keyID)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                description
                statusContent
            }
            .padding(8)
        } label: {
            HStack {
                Label("GitHub", systemImage: "checkmark.shield")
                    .labelStyle(.largeIcon)
                Spacer()
                if state.availableGitHubAccounts.count > 1 {
                    accountPicker
                }
                Button {
                    Task { await state.refreshGitHubRegisteredKeys() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Re-check GitHub")
            }
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: deleteBinding,
            presenting: pendingDelete
        ) { key in
            Button("Remove from GitHub", role: .destructive) {
                Task { await state.deleteGitHubKey(key) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("Commits previously signed with this key keep their Verified badge — GitHub stores the signature at sign time.")
        }
        .confirmationDialog(
            "Replace GitHub key?",
            isPresented: replaceBinding,
            presenting: pendingReplace
        ) { pending in
            Button("Replace") {
                Task { await state.replaceGitHubKey(removing: pending.remote, with: pending.local) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { pending in
            Text("The new key (\(pending.local.primaryUserID)) will be uploaded first. The old key (\(pending.remote.keyID)) is removed only after the upload succeeds.")
        }
        .confirmationDialog(
            "Refresh GitHub key?",
            isPresented: refreshBinding,
            presenting: pendingRefresh
        ) { pending in
            Button("Refresh") {
                Task { await state.refreshGitHubKey(pending.remote, with: pending.local) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("GitHub deduplicates by key ID, so the stale registration is removed first, then the current local copy is uploaded. Previously signed commits keep their Verified badge.")
        }
        .sheet(item: $pendingRename) { pending in
            RenameSheet(pending: pending) { newName in
                Task { await state.renameGitHubKey(pending.remote, with: pending.local, name: newName) }
            }
        }
    }

    private var accountPicker: some View {
        Menu {
            ForEach(state.availableGitHubAccounts, id: \.self) { account in
                Button {
                    Task { await state.selectGitHubAccount(account) }
                } label: {
                    Label(account, systemImage: state.gitHubUsername == account ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                Text(state.gitHubUsername ?? "Account")
                    .font(.caption)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch which GitHub account to operate on")
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let user = state.gitHubUsername {
                Text("Keys on the **\(user)** account.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("GPG keys registered with your GitHub account.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Commits to org repos verify against these same keys — no separate org upload needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state.gitHubKeyCheck {
        case .notChecked, .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking GitHub…").font(.caption).foregroundStyle(.secondary)
            }
        case .unavailable(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .scopeRequired(let command):
            ScopeRequiredView(command: command)
        case .loaded(let keys):
            keysList(keys)
        }
    }

    @ViewBuilder
    private func keysList(_ keys: [GitHubRegisteredKey]) -> some View {
        if keys.isEmpty {
            Text("No GPG keys on GitHub yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(keys) { key in
                    GitHubKeyRow(
                        registered: key,
                        match: localMatch(for: key),
                        defaultKey: defaultSecretKey,
                        onDelete: { pendingDelete = key },
                        onReplace: { local in pendingReplace = PendingKeyAction(remote: key, local: local) },
                        onRefresh: { local in pendingRefresh = PendingKeyAction(remote: key, local: local) },
                        onRename: { local in pendingRename = PendingKeyAction(remote: key, local: local) }
                    )
                    if key.id != keys.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(.rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }

        if let key = defaultSecretKey, !defaultKeyIsRegistered {
            Button("Upload current default key", systemImage: "arrow.up.circle") {
                Task { await state.uploadKeyToGitHub(key) }
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
    }

    private func localMatch(for registered: GitHubRegisteredKey) -> GPGKey? {
        state.secretKeys.first { registered.matches(keyID: $0.keyID) }
    }

    private var deleteDialogTitle: String {
        guard let key = pendingDelete else { return "Remove key from GitHub?" }
        let name = key.name ?? key.keyID
        return "Remove “\(name)” from GitHub?"
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var replaceBinding: Binding<Bool> {
        Binding(get: { pendingReplace != nil }, set: { if !$0 { pendingReplace = nil } })
    }

    private var refreshBinding: Binding<Bool> {
        Binding(get: { pendingRefresh != nil }, set: { if !$0 { pendingRefresh = nil } })
    }
}

private struct RenameSheet: View {
    let pending: PendingKeyAction
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename GitHub key")
                .font(.headline)
            Text("GitHub doesn't allow editing the name directly, so this will delete and re-upload the key with the new name. Past commits keep their Verified badge.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Display name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            name = pending.remote.name ?? pending.remote.primaryEmail ?? ""
        }
    }
}

private struct ScopeRequiredView: View {
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(.orange)
                Text("Grant GitHub GPG-keys access:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(command)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: .rect(cornerRadius: 4))
                    .textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }
}

#if DEBUG
#Preview {
    GitHubKeysCard()
        .environment(GPGAppState.preview)
        .padding()
        .frame(width: 600)
}
#endif
