import SwiftUI

struct SigningView: View {
    @Environment(GPGAppState.self) private var state
    @State private var draft: GitSigningConfiguration = .empty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeaderView(title: "Signing", subtitle: "Configure Git signing and manage your GitHub-registered keys.")
                GitSigningCard(draft: $draft)
                GitHubKeysCard()
            }
            .padding(24)
        }
        .onAppear { draft = state.gitSigning }
        .onChange(of: state.gitSigning) { _, newValue in
            draft = newValue
        }
    }
}

#if DEBUG
#Preview {
    SigningView()
        .environment(GPGAppState.preview)
        .frame(width: 720, height: 600)
}
#endif
