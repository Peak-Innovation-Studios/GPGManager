import SwiftUI

/// A SecureField that swaps to a plain TextField when `isVisible` is on.
/// Pass `showsToggle: true` on a single field in a group to render a shared
/// eye/eye-slash button at the trailing edge.
struct RevealableSecureField: View {
    let title: String
    @Binding var text: String
    @Binding var isVisible: Bool
    var showsToggle: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            field
                .textContentType(.newPassword)
            if showsToggle {
                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isVisible ? "Hide passphrase" : "Show passphrase")
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        if isVisible {
            TextField(title, text: $text)
        } else {
            SecureField(title, text: $text)
        }
    }
}
