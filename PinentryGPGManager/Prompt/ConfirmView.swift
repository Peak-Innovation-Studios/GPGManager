import SwiftUI

struct ConfirmView: View {
    let request: PinentryRequest
    let oneButton: Bool
    let onConfirm: () -> Void
    let onDecline: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AppIconView(size: 56, fallbackSystemImage: "exclamationmark.shield")
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.effectiveTitle)
                        .font(.headline)
                    Text("GPG Manager")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let description = request.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = request.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                if !oneButton {
                    Button(request.notOkLabel ?? "No", action: onDecline)
                    Button(request.effectiveCancel, role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                Button(request.effectiveOK, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
