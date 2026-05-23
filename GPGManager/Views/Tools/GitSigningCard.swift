import SwiftUI

struct GitSigningCard: View {
    @Environment(GPGAppState.self) private var state
    @Binding var draft: GitSigningConfiguration
    @State private var showsRepoManager = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                TargetPicker(showsRepoManager: $showsRepoManager)

                if let detail = state.gitConfigScope.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Divider()

                if state.secretKeys.isEmpty {
                    Text("No secret keys are available. Create one in the Keys tab first.")
                        .foregroundStyle(.secondary)
                } else {
                    editableFields
                    Divider()
                    gpgPathRow
                    GitIdentityRow()
                    actionRow
                }
            }
            .padding(8)
        } label: {
            Label("Git Signing", systemImage: "signature")
                .labelStyle(.largeIcon)
        }
        .sheet(isPresented: $showsRepoManager) {
            ManageRepositoriesView()
                .environment(state)
        }
    }

    private var editableFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Picker("Signing Key", selection: signingKeyBinding) {
                    Text("None").tag("")
                    ForEach(state.secretKeys) { key in
                        Text(displayName(for: key)).tag(key.fingerprint)
                    }
                    if let raw = draft.signingKey,
                       !raw.isEmpty,
                       GPGKey.match(signingKey: raw, in: state.secretKeys) == nil {
                        Text("Unknown key (\(raw.suffix(16)))").tag(raw)
                    }
                }
                InheritanceCaption(overriddenLocally: state.gitSigning.signingKeyOverriddenLocally)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Sign commits by default", isOn: $draft.signsCommits)
                InheritanceCaption(overriddenLocally: state.gitSigning.signsCommitsOverriddenLocally)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Sign tags by default", isOn: $draft.signsTags)
                InheritanceCaption(overriddenLocally: state.gitSigning.signsTagsOverriddenLocally)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Show signature info in git log", isOn: $draft.showsLogSignatures)
                    .help("Sets log.showSignature. When on, `git log` displays whether each commit is signed and verified.")
                InheritanceCaption(overriddenLocally: state.gitSigning.showsLogSignaturesOverriddenLocally)
            }
        }
    }

    private var gpgPathRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent("GPG path") {
                Text(state.selectedGPGPath.isEmpty ? "Not set" : state.selectedGPGPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if case .repository = state.gitConfigScope {
                Text("Stored globally for all repos")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Apply", systemImage: "checkmark.seal") {
                Task { await apply() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.selectedGPGPath.isEmpty || draft == state.gitSigning)

            Spacer()

            if case .repository = state.gitConfigScope {
                Button("Forget Repository", role: .destructive) {
                    Task { await forgetCurrent() }
                }
            }
        }
    }

    private var signingKeyBinding: Binding<String> {
        Binding {
            if let raw = draft.signingKey, !raw.isEmpty {
                if let match = GPGKey.match(signingKey: raw, in: state.secretKeys) {
                    return match.fingerprint
                }
                return raw
            }
            return ""
        } set: { newValue in
            draft.signingKey = newValue.isEmpty ? nil : newValue
        }
    }

    private func displayName(for key: GPGKey) -> String {
        let suffix = String(key.keyID.suffix(8))
        return "\(key.primaryUserID) – \(suffix)"
    }

    private func apply() async {
        var configuration = draft
        if !state.selectedGPGPath.isEmpty {
            configuration.gpgProgram = state.selectedGPGPath
        }
        await state.applyGitSigningConfiguration(configuration)
    }

    private func forgetCurrent() async {
        guard case .repository(let path) = state.gitConfigScope,
              let repo = state.rememberedRepos.first(where: { $0.path == path }) else {
            return
        }
        await state.forgetRepository(repo)
    }
}

struct InheritanceCaption: View {
    @Environment(GPGAppState.self) private var state
    let overriddenLocally: Bool

    var body: some View {
        if case .repository = state.gitConfigScope {
            Text(overriddenLocally ? "Set in this repo" : "Inherited from global")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct GitIdentityRow: View {
    @Environment(GPGAppState.self) private var state

    var body: some View {
        if let name = state.gitSigning.userName, let email = state.gitSigning.userEmail {
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("Git identity") {
                    Text("\(name) <\(email)>")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                InheritanceCaption(overriddenLocally: state.gitSigning.userOverriddenLocally)
            }
        } else if case .repository = state.gitConfigScope {
            LabeledContent("Git identity") {
                Text("Not set — Git will refuse to commit until you set user.name and user.email.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct TargetPicker: View {
    @Environment(GPGAppState.self) private var state
    @Binding var showsRepoManager: Bool

    private enum Selection: Hashable {
        case scope(GitConfigScope)
        case addRepository
        case manageRepositories
    }

    var body: some View {
        Picker("Target", selection: selectionBinding) {
            Text("Global (~/.gitconfig)").tag(Selection.scope(.global))
            if !state.rememberedRepos.isEmpty {
                Divider()
                ForEach(state.rememberedRepos) { repo in
                    Text(repo.displayName).tag(Selection.scope(.repository(path: repo.path)))
                }
                Text("Manage Repositories…").tag(Selection.manageRepositories)
            }
            Divider()
            Text("Add Repository…").tag(Selection.addRepository)
        }
    }

    private var selectionBinding: Binding<Selection> {
        Binding {
            .scope(state.gitConfigScope)
        } set: { newValue in
            switch newValue {
            case .scope(let scope):
                Task { await state.setGitConfigScope(scope) }
            case .addRepository:
                Task { await state.chooseRepository() }
            case .manageRepositories:
                showsRepoManager = true
            }
        }
    }
}
