import SwiftUI

struct ConfirmView: View {
    let request: PinentryRequest
    let oneButton: Bool
    let onConfirm: () -> Void
    let onDecline: () -> Void
    let onCancel: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 72

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let description = request.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quinary, in: .rect(cornerRadius: 10))
                }

                if let error = request.errorMessage, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
                        .accessibilityAddTraits(.isStaticText)
                }

                HStack(spacing: 10) {
                    Spacer()
                    if !oneButton {
                        Button(request.notOkLabel ?? "No", action: onDecline)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        Button(request.effectiveCancel, role: .cancel, action: onCancel)
                            .keyboardShortcut(.cancelAction)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                    Button(request.effectiveOK, action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(minWidth: 460, idealWidth: 500, maxWidth: 620)
        .fixedSize(horizontal: false, vertical: true)
        .containerBackground(.regularMaterial, for: .window)
        .onChange(of: request.errorMessage) { _, newValue in
            announce(newValue)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            AppIconView(size: iconSize, fallbackSystemImage: "exclamationmark.shield")
            VStack(spacing: 2) {
                Text(request.effectiveTitle)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("GPG Manager")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(request.effectiveTitle). GPG Manager."))
    }

    private func announce(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        AccessibilityNotification.Announcement(message).post()
    }
}

#if DEBUG
#Preview("Confirm — two button") {
    ConfirmView(
        request: PinentryRequest(
            title: "Replace existing key?",
            description: "A secret key with this user ID already exists. Importing will replace the existing key and any associated subkeys. This cannot be undone."
        ),
        oneButton: false,
        onConfirm: {},
        onDecline: {},
        onCancel: {}
    )
}

#Preview("Confirm — one button") {
    ConfirmView(
        request: PinentryRequest(
            title: "Key generated",
            description: "Your new OpenPGP key was generated successfully and added to the keyring."
        ),
        oneButton: true,
        onConfirm: {},
        onDecline: {},
        onCancel: {}
    )
}
#endif
