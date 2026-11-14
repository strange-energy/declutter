import Foundation
import SwiftUI

/// Summary payload shown in `StorageCelebrationView` after a successful batch deletion.
public struct BatchCommitReceipt: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let deletedCount: Int
    public let reclaimedBytes: Int64
    public let updatedLifetimeStats: LifetimeStatsSnapshot
    /// Optional Google Photos album URL if any cloud-only items were staged to `"To Delete - SwipeDeck"`
    /// so the user can open Google Photos in one tap to empty them.
    public let googlePhotosTrashAlbumURL: URL?
    public let cloudStagedCount: Int

    public var formattedReclaimedSize: String {
        ByteCountFormatter.string(fromByteCount: reclaimedBytes, countStyle: .file)
    }

    public init(
        deletedCount: Int,
        reclaimedBytes: Int64,
        updatedLifetimeStats: LifetimeStatsSnapshot,
        googlePhotosTrashAlbumURL: URL? = nil,
        cloudStagedCount: Int = 0
    ) {
        self.deletedCount = deletedCount
        self.reclaimedBytes = reclaimedBytes
        self.updatedLifetimeStats = updatedLifetimeStats
        self.googlePhotosTrashAlbumURL = googlePhotosTrashAlbumURL
        self.cloudStagedCount = cloudStagedCount
    }
}

/// Manages Stage 1 (In-App Staging Trash Bin) & Stage 2 (Batch Commit & Rescue Sheet) of the
/// Two-Stage Deletion Pipeline (PRD Section 4.2).
@MainActor
@Observable
public final class TrashStagingViewModel {
    /// Ordered list of items currently staged in the trash queue.
    public private(set) var stagedItems: [StagedTrashSnapshot] = []
    /// Set of item IDs marked as "Rescued" inside the Batch Commit Review Sheet before final deletion.
    public var rescuedItemIDs: Set<String> = []
    /// Controls presentation of the Review & Commit Sheet.
    public var isPresentingCommitSheet = false
    /// Controls presentation of the post-commit Storage Celebration Sheet.
    public var latestCommitReceipt: BatchCommitReceipt?
    public private(set) var isExecutingBatchDelete = false
    public var errorMessage: String?

    private let ledger: LedgerActor
    private let deleteExecutor = BatchDeleteExecutor()

    public init(ledger: LedgerActor) {
        self.ledger = ledger
    }

    // MARK: - Computed Metrics

    public var stagedCount: Int {
        stagedItems.count
    }

    public var totalStagedBytes: Int64 {
        stagedItems.reduce(0) { $0 + $1.fileSizeBytes }
    }

    public var formattedTotalStagedSize: String {
        ByteCountFormatter.string(fromByteCount: totalStagedBytes, countStyle: .file)
    }

    /// Items that will actually be deleted (staged items minus any rescued items in the sheet).
    public var itemsPendingDeletion: [StagedTrashSnapshot] {
        stagedItems.filter { !rescuedItemIDs.contains($0.id) }
    }

    public var pendingDeletionBytes: Int64 {
        itemsPendingDeletion.reduce(0) { $0 + $1.fileSizeBytes }
    }

    public var formattedPendingDeletionSize: String {
        ByteCountFormatter.string(fromByteCount: pendingDeletionBytes, countStyle: .file)
    }

    // MARK: - Lifecycle & State Sync

    public func reloadFromLedger() async {
        do {
            stagedItems = try await ledger.fetchStagedTrashItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stages a left-swiped asset into the in-app trash queue immediately and persists it to SwiftData.
    public func stageForTrash(asset: MediaAsset, sourceDeckID: String?) {
        let initialBytes = asset.fileSizeBytes
        let snapshot = StagedTrashSnapshot(
            id: asset.id,
            fileSizeBytes: initialBytes,
            mediaKind: asset.kind,
            stagedAt: .now
        )

        if let existingIndex = stagedItems.firstIndex(where: { $0.id == asset.id }) {
            stagedItems[existingIndex] = snapshot
        } else {
            stagedItems.insert(snapshot, at: 0)
        }
        rescuedItemIDs.remove(asset.id)

        Task {
            let resolvedBytes: Int64
            if initialBytes > 0 {
                resolvedBytes = initialBytes
            } else {
                resolvedBytes = await AssetMetadataExtractor.shared.fileSizeBytes(for: asset.id)
            }

            if resolvedBytes != initialBytes,
               let idx = self.stagedItems.firstIndex(where: { $0.id == asset.id }) {
                self.stagedItems[idx] = StagedTrashSnapshot(
                    id: asset.id,
                    fileSizeBytes: resolvedBytes,
                    mediaKind: asset.kind,
                    stagedAt: snapshot.stagedAt
                )
            }

            try? await ledger.recordDisposition(
                assetID: asset.id,
                disposition: .stagedTrash,
                fileSizeBytes: resolvedBytes,
                mediaKind: asset.kind,
                sourceDeckID: sourceDeckID
            )
        }
    }

    /// Removes an item from the staging trash queue (used when Undoing a left-swipe or rescuing immediately).
    public func unstageFromTrash(assetID: String) {
        stagedItems.removeAll { $0.id == assetID }
        rescuedItemIDs.remove(assetID)
        Task {
            try? await ledger.removeDisposition(assetID: assetID)
        }
    }

    /// Toggles rescue state for a tile inside `BatchCommitSheetView` (PRD Section 4.2).
    public func toggleRescue(for assetID: String) {
        HapticEngine.shared.fireSelectionTick()
        if rescuedItemIDs.contains(assetID) {
            rescuedItemIDs.remove(assetID)
        } else {
            rescuedItemIDs.insert(assetID)
        }
    }

    /// Commits all non-rescued items to iOS system trash (`PHAssetChangeRequest.deleteAssets`)
    /// and restores any rescued items back to Kept/Unstaged state.
    public func commitBatchDeletion(onComplete: (@MainActor () -> Void)? = nil) async {
        let toDelete = itemsPendingDeletion
        let rescuedIDs = Array(rescuedItemIDs)

        guard !toDelete.isEmpty || !rescuedIDs.isEmpty else {
            isPresentingCommitSheet = false
            return
        }

        isExecutingBatchDelete = true
        errorMessage = nil

        do {
            // 1. Restore any rescued items first
            for rescuedID in rescuedIDs {
                try? await ledger.removeDisposition(assetID: rescuedID)
            }

            // 2. Separate local Apple PhotoKit items vs. Google Photos Cloud items
            if !toDelete.isEmpty {
                let cloudItems = toDelete.filter { $0.id.hasPrefix("gphoto_") }
                let localItems = toDelete.filter { !$0.id.hasPrefix("gphoto_") }

                if !localItems.isEmpty {
                    try await deleteExecutor.executeBatchDeletion(assetIDs: localItems.map(\.id))
                }

                var googleAlbumURL: URL?
                if !cloudItems.isEmpty {
                    googleAlbumURL = try await GooglePhotosCloudService.shared.commitCloudTrashItems(
                        assetIDs: cloudItems.map(\.id)
                    )
                }

                let updatedStats = try await ledger.finalizeBatchDeletion(deletedItems: toDelete)
                let reclaimedBytes = toDelete.reduce(0) { $0 + $1.fileSizeBytes }

                HapticEngine.shared.fireBatchDeleteDoubleTap()

                stagedItems.removeAll()
                rescuedItemIDs.removeAll()
                isExecutingBatchDelete = false
                isPresentingCommitSheet = false

                latestCommitReceipt = BatchCommitReceipt(
                    deletedCount: toDelete.count,
                    reclaimedBytes: reclaimedBytes,
                    updatedLifetimeStats: updatedStats,
                    googlePhotosTrashAlbumURL: googleAlbumURL,
                    cloudStagedCount: cloudItems.count
                )
                onComplete?()
            } else {
                // Only rescues occurred
                stagedItems = try await ledger.fetchStagedTrashItems()
                rescuedItemIDs.removeAll()
                isExecutingBatchDelete = false
                isPresentingCommitSheet = false
                onComplete?()
            }
        } catch {
            isExecutingBatchDelete = false
            errorMessage = error.localizedDescription
        }
    }
}
