import SwiftUI

/// Stage 2 of the Two-Stage Deletion Pipeline (`Review & Commit Sheet`, PRD Section 4.2):
/// - Displays a compact 3-column grid of all left-swiped items.
/// - Allows the user to tap any thumbnail to rescue it before permanent commit.
/// - Tapping "Delete N Items" triggers a single native iOS `PHAssetChangeRequest.deleteAssets` confirmation prompt.
public struct BatchCommitSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var trashVM: TrashStagingViewModel
    public let onCommitSuccess: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    public init(trashVM: TrashStagingViewModel, onCommitSuccess: @escaping () -> Void) {
        self.trashVM = trashVM
        self.onCommitSuccess = onCommitSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                SwipeDeckTheme.backgroundPrimary
                    .ignoresSafeArea()

                if trashVM.stagedItems.isEmpty {
                    emptyTrashState
                } else {
                    VStack(spacing: 0) {
                        headerInstructionBanner

                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(trashVM.stagedItems) { item in
                                    StagedTrashGridTile(
                                        item: item,
                                        isRescued: trashVM.rescuedItemIDs.contains(item.id)
                                    ) {
                                        trashVM.toggleRescue(for: item.id)
                                    }
                                }
                            }
                            .padding(16)
                        }

                        bottomCommitBar
                    }
                }
            }
            .navigationTitle("Staging Trash Bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(SwipeDeckTheme.textSecondary)
                }

                if !trashVM.rescuedItemIDs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select All") {
                            trashVM.rescuedItemIDs.removeAll()
                        }
                        .font(SwipeDeckTypography.roundedCounter(14))
                        .foregroundStyle(SwipeDeckTheme.accentDefer)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var headerInstructionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .foregroundStyle(SwipeDeckTheme.accentKeep)
            Text("Tap any photo to **rescue** it before moving the rest to iOS Recently Deleted.")
                .font(SwipeDeckTypography.body(13))
                .foregroundStyle(SwipeDeckTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SwipeDeckTheme.surfaceElevated)
    }

    private var bottomCommitBar: some View {
        VStack(spacing: 10) {
            if let errorMessage = trashVM.errorMessage {
                Text(errorMessage)
                    .font(SwipeDeckTypography.body(12))
                    .foregroundStyle(SwipeDeckTheme.accentDelete)
                    .multilineTextAlignment(.center)
            }

            let pendingCount = trashVM.itemsPendingDeletion.count
            let rescuedCount = trashVM.rescuedItemIDs.count

            Button {
                Task {
                    await trashVM.commitBatchDeletion {
                        onCommitSuccess()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if trashVM.isExecutingBatchDelete {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: pendingCount > 0 ? "trash.fill" : "checkmark.shield.fill")
                    }

                    if pendingCount > 0 {
                        Text("Delete \(pendingCount) Items (\(trashVM.formattedPendingDeletionSize))")
                            .font(SwipeDeckTypography.roundedHeadline(17, weight: .bold))
                    } else {
                        Text("Rescue All \(rescuedCount) Items")
                            .font(SwipeDeckTypography.roundedHeadline(17, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    pendingCount > 0 ? SwipeDeckTheme.accentDelete : SwipeDeckTheme.accentKeep,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(trashVM.isExecutingBatchDelete)

            Text("Confirmed items stay in iOS 'Recently Deleted' for 30 days.")
                .font(SwipeDeckTypography.body(12))
                .foregroundStyle(SwipeDeckTheme.textTertiary)
        }
        .padding(16)
        .background(SwipeDeckTheme.surfaceElevated)
    }

    private var emptyTrashState: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash.slash.fill")
                .font(.system(size: 42))
                .foregroundStyle(SwipeDeckTheme.textTertiary)
            Text("Staging Trash Bin is Empty")
                .font(SwipeDeckTypography.roundedHeadline(18))
                .foregroundStyle(SwipeDeckTheme.textPrimary)
            Text("Swipe left on photos or videos during a triage session to stage them here.")
                .font(SwipeDeckTypography.body(14))
                .foregroundStyle(SwipeDeckTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }
}

/// Individual grid cell inside `BatchCommitSheetView` with file-size badge and tap-to-rescue badge.
private struct StagedTrashGridTile: View {
    let item: StagedTrashSnapshot
    let isRescued: Bool
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SwipeDeckTheme.surfaceElevated)
                    .aspectRatio(1.0, contentMode: .fit)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .aspectRatio(1.0, contentMode: .fill)
                        .clipped()
                        .opacity(isRescued ? 0.45 : 1.0)
                } else {
                    ProgressView()
                        .tint(.white)
                }

                // Bottom-left byte size badge + video icon
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(isRescued ? SwipeDeckTheme.accentKeep : SwipeDeckTheme.accentDelete)
                                .frame(width: 24, height: 24)
                            Image(systemName: isRescued ? "heart.fill" : "trash.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(6)

                    Spacer()

                    HStack(spacing: 4) {
                        if item.mediaKind == .video {
                            Image(systemName: "video.fill")
                                .font(.system(size: 9))
                        }
                        if item.fileSizeBytes > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file))
                                .exifMonoStyle(size: 10, color: .white)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    )
                }

                if isRescued {
                    Text("RESCUED")
                        .exifMonoStyle(size: 10, color: SwipeDeckTheme.accentKeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.82), in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(SwipeDeckTheme.accentKeep, lineWidth: 1.5)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isRescued ? SwipeDeckTheme.accentKeep : SwipeDeckTheme.accentDelete.opacity(0.45),
                        lineWidth: isRescued ? 2.5 : 1.0
                    )
            )
        }
        .buttonStyle(.plain)
        .task(id: item.id) {
            AssetPrefetchPipeline.shared.requestThumbnail(for: item.id) { img in
                self.thumbnail = img
            }
        }
    }
}
