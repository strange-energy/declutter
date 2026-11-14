import SwiftUI

/// Interactive Trash Staging Pill in the Top Bar (`🗑️ 28 • 145 MB`) (PRD Section 4.2 & 6.2).
/// Tapping opens the Stage 2 Review & Commit Sheet (`BatchCommitSheetView`).
public struct TrashPillButton: View {
    public let count: Int
    public let formattedBytes: String
    public let onTap: () -> Void

    public init(count: Int, formattedBytes: String, onTap: @escaping () -> Void) {
        self.count = count
        self.formattedBytes = formattedBytes
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: count > 0 ? "trash.fill" : "trash")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(count > 0 ? SwipeDeckTheme.accentDelete : SwipeDeckTheme.textSecondary)

                Text("\(count)")
                    .roundedStatStyle(size: 14, color: SwipeDeckTheme.textPrimary)
                    .contentTransition(.numericText())

                if count > 0 {
                    Text("•")
                        .foregroundStyle(SwipeDeckTheme.textTertiary)
                    Text(formattedBytes)
                        .exifMonoStyle(size: 12, color: SwipeDeckTheme.accentDelete)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(count > 0 ? SwipeDeckTheme.accentDelete.opacity(0.16) : SwipeDeckTheme.surfaceElevated)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                count > 0 ? SwipeDeckTheme.accentDelete.opacity(0.55) : SwipeDeckTheme.borderSubtle,
                                lineWidth: 1
                            )
                    )
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: count)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Staged Trash: \(count) items, \(formattedBytes)")
    }
}
