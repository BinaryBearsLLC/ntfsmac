import SwiftUI

/// Compact, transient state only: Verified Copy remains a per-drive overflow action rather than
/// becoming another permanent section in the intentionally small menu-bar interface.
public struct VerifiedCopyStatusView: View {
    @ObservedObject public var controller: VerifiedCopyController
    @Environment(\.colorScheme) private var colorScheme

    public init(controller: VerifiedCopyController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                statusIcon
                Text("Verified Copy")
                    .font(.system(size: 11, weight: .semibold))
                if !controller.volumeName.isEmpty {
                    Text("· \(controller.volumeName)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if controller.isActive {
                    Button("Cancel") { controller.cancel() }
                        .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                        .ntfsmacKeyboardFocus()
                        .disabled(controller.phase == .cancelling)
                } else {
                    Button { controller.dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .ntfsmacKeyboardFocus()
                    .accessibilityLabel("Dismiss Verified Copy result")
                }
            }

            if !controller.sourceName.isEmpty || !controller.destinationName.isEmpty {
                Text("\(controller.sourceName) → \(controller.destinationName)")
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(controller.message)
                .font(.system(size: 10.5))
                .foregroundStyle(messageColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Verified Copy status")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch controller.phase {
        case .running, .cancelling:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ntfsGreen)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.ntfsYellow)
        case .cancelled:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    private var messageColor: Color {
        controller.phase == .failed ? .ntfsYellow : .secondary
    }
}
