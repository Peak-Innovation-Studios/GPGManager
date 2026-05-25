import SwiftUI

struct ManageRepositoriesView: View {
    @Environment(GPGAppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 540, height: 380)
    }

    private var header: some View {
        HStack {
            Text("Remembered Repositories")
                .font(.headline)
            Spacer()
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if state.rememberedRepos.isEmpty {
            ContentUnavailableView(
                "No Remembered Repositories",
                systemImage: "folder.badge.questionmark",
                description: Text("Add a repository from the Tools tab's Target dropdown.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(state.rememberedRepos) { repo in
                    RepositoryRow(repo: repo)
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}

private struct RepositoryRow: View {
    @Environment(GPGAppState.self) private var state
    let repo: RememberedRepo

    @State private var draftName: String = ""

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Display name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit() }
                Text(repo.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Button("Save") {
                commit()
            }
            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines) == (repo.name ?? ""))

            Button("Forget", role: .destructive) {
                Task { await state.forgetRepository(repo) }
            }
        }
        .padding(.vertical, 4)
        .onAppear { draftName = repo.name ?? "" }
        .onChange(of: repo.name) { _, newValue in
            draftName = newValue ?? ""
        }
    }

    private func commit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        state.renameRepository(repo, to: trimmed.isEmpty ? nil : trimmed)
    }
}

#Preview {
    ManageRepositoriesView()
        .environment(GPGAppState.preview)
}
