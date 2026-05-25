import SwiftUI

struct ConfirmView: View {
    let request: PinentryRequest
    let oneButton: Bool
    let onConfirm: () -> Void
    let onDecline: () -> Void
    let onCancel: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header

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
                        .accessibilityAddTraits(.isStaticText)
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
        }
        .frame(width: 420)
        .onChange(of: request.errorMessage) { _, newValue in
            announce(newValue)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconView(size: iconSize, fallbackSystemImage: "exclamationmark.shield")
            VStack(alignment: .leading, spacing: 2) {
                Text(request.effectiveTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("GPG Manager")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(request.effectiveTitle). GPG Manager."))
    }

    private func announce(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        AccessibilityNotification.Announcement(message).post()
    }
}
