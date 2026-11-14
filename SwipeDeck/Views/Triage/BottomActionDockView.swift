import SwiftUI

/// Bottom Action Dock occupying ~10% screen height in the one-handed thumb zone (PRD Section 6.2):
/// Four circular glassmorphic (`UltraThinMaterial`) buttons mirroring the 4 swipe gestures:
/// - Undo (Amber `#FFD60A`)
/// - Trash (Coral Red `#FF453A`)
/// - Skip / Defer to Back (Electric Blue `#0A84FF`)
/// - Keep (Emerald Green `#30D158`)
public struct BottomActionDockView: View {
    public let canUndo: Bool
    public let isEnabled: Bool
    public let onAction: (SwipeAction) -> Void

    public init(
        canUndo: Bool,
        isEnabled: Bool,
        onAction: @escaping (SwipeAction) -> Void
    ) {
        self.canUndo = canUndo
        self.isEnabled = isEnabled
        self.onAction = onAction
    }

    public var body: some View {
        HStack(spacing: 22) {
            dockButton(
                action: .undo,
                icon: "arrow.uturn.backward",
                label: "Undo",
                accent: SwipeDeckTheme.accentUndo,
                size: 52,
                iconSize: 20,
                disabled: !canUndo
            )

            dockButton(
                action: .trash,
                icon: "trash.fill",
                label: "Trash",
                accent: SwipeDeckTheme.accentDelete,
                size: 64,
                iconSize: 24,
                disabled: !isEnabled
            )

            dockButton(
                action: .deferToBack,
                icon: "arrow.up.to.line",
                label: "Skip",
                accent: SwipeDeckTheme.accentDefer,
                size: 52,
                iconSize: 20,
                disabled: !isEnabled
            )

            dockButton(
                action: .keep,
                icon: "checkmark",
                label: "Keep",
                accent: SwipeDeckTheme.accentKeep,
                size: 64,
                iconSize: 25,
                disabled: !isEnabled
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func dockButton(
        action: SwipeAction,
        icon: String,
        label: String,
        accent: Color,
        size: CGFloat,
        iconSize: CGFloat,
        disabled: Bool
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: size, height: size)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    disabled ? SwipeDeckTheme.borderSubtle.opacity(0.4) : accent.opacity(0.65),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: disabled ? .clear : accent.opacity(0.22), radius: 10, y: 4)

                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundStyle(disabled ? SwipeDeckTheme.textTertiary : accent)
                }

                Text(label)
                    .font(SwipeDeckTypography.roundedCounter(11, weight: .semibold))
                    .foregroundStyle(disabled ? SwipeDeckTheme.textTertiary : SwipeDeckTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
        .accessibilityLabel(label)
    }
}
