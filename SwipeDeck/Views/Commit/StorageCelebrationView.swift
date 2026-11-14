import SwiftUI

/// Post-commit celebration screen displaying storage reclaimed in the current batch and cumulative lifetime stats (PRD Section 8 Milestone 2).
public struct StorageCelebrationView: View {
    public let receipt: BatchCommitReceipt
    public let onDismiss: () -> Void

    public init(receipt: BatchCommitReceipt, onDismiss: @escaping () -> Void) {
        self.receipt = receipt
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            SwipeDeckTheme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                CompanionAvatarView(
                    progress: receipt.updatedLifetimeStats.companionProgress,
                    containerSize: 108,
                    isInteractive: true
                )

                VStack(spacing: 10) {
                    Text(receipt.formattedReclaimedSize)
                        .font(SwipeDeckTypography.roundedTitle(44, weight: .heavy))
                        .foregroundStyle(SwipeDeckTheme.accentKeep)

                    Text("Storage Reclaimed!")
                        .font(SwipeDeckTypography.roundedTitle(24, weight: .bold))
                        .foregroundStyle(SwipeDeckTheme.textPrimary)

                    Text("Moved \(receipt.deletedCount) clutter items to iOS Recently Deleted.")
                        .font(SwipeDeckTypography.body(15))
                        .foregroundStyle(SwipeDeckTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                // Cumulative Lifetime Telemetry Card
                VStack(spacing: 14) {
                    Text("LIFETIME IMPACT")
                        .exifMonoStyle(size: 11, color: SwipeDeckTheme.textSecondary)

                    HStack(spacing: 24) {
                        statColumn(
                            value: receipt.updatedLifetimeStats.formattedBytesReclaimed,
                            label: "Total Saved"
                        )
                        Divider()
                            .frame(height: 36)
                            .overlay(SwipeDeckTheme.borderSubtle)
                        statColumn(
                            value: "\(receipt.updatedLifetimeStats.totalItemsDeleted)",
                            label: "Items Trashed"
                        )
                        Divider()
                            .frame(height: 36)
                            .overlay(SwipeDeckTheme.borderSubtle)
                        statColumn(
                            value: "\(receipt.updatedLifetimeStats.totalAssetsKept)",
                            label: "Curated Keeps"
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(SwipeDeckTheme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)

                Spacer()

                if let googleURL = receipt.googlePhotosTrashAlbumURL, receipt.cloudStagedCount > 0 {
                    Button {
                        UIApplication.shared.open(googleURL)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.square.fill")
                            Text("Open '\(GooglePhotosCloudService.stagingAlbumTitle)' in Google Photos")
                                .font(SwipeDeckTypography.roundedHeadline(14, weight: .bold))
                        }
                        .foregroundStyle(SwipeDeckTheme.accentDefer)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(SwipeDeckTheme.accentDefer.opacity(0.15))
                                .overlay(
                                    Capsule().strokeBorder(SwipeDeckTheme.accentDefer.opacity(0.5), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                }

                Button(action: onDismiss) {
                    Text("Continue Decluttering")
                        .font(SwipeDeckTypography.roundedHeadline(17, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(SwipeDeckTheme.accentKeep, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .roundedStatStyle(size: 18, color: SwipeDeckTheme.textPrimary)
            Text(label)
                .font(SwipeDeckTypography.body(12))
                .foregroundStyle(SwipeDeckTheme.textSecondary)
        }
    }
}
