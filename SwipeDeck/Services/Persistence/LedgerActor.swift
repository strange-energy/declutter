import Foundation
import SwiftData

/// Sendable snapshot of a staged trash item stored in SwiftData.
public struct StagedTrashSnapshot: Identifiable, Hashable, Sendable {
    public let id: String // PHAsset.localIdentifier
    public let fileSizeBytes: Int64
    public let mediaKind: MediaAsset.Kind
    public let stagedAt: Date

    public init(id: String, fileSizeBytes: Int64, mediaKind: MediaAsset.Kind, stagedAt: Date) {
        self.id = id
        self.fileSizeBytes = fileSizeBytes
        self.mediaKind = mediaKind
        self.stagedAt = stagedAt
    }
}

/// Sendable snapshot of lifetime statistics.
public struct LifetimeStatsSnapshot: Equatable, Sendable {
    public let totalPhotosDeleted: Int
    public let totalVideosDeleted: Int
    public let totalBytesReclaimed: Int64
    public let totalAssetsKept: Int
    public let totalSessionsCompleted: Int
    public let currentStagedCount: Int

    public var totalItemsDeleted: Int {
        totalPhotosDeleted + totalVideosDeleted
    }

    /// Total swipes/reviews across the app's lifetime (Kept + Deleted + Currently Staged).
    public var totalUsageSwipes: Int {
        totalAssetsKept + totalItemsDeleted + currentStagedCount
    }

    public var companionProgress: AvatarCompanionProgress {
        AvatarCompanionProgress(
            totalSwipes: totalUsageSwipes,
            sessionsCompleted: totalSessionsCompleted
        )
    }

    public var formattedBytesReclaimed: String {
        ByteCountFormatter.string(fromByteCount: totalBytesReclaimed, countStyle: .file)
    }

    public init(
        totalPhotosDeleted: Int = 0,
        totalVideosDeleted: Int = 0,
        totalBytesReclaimed: Int64 = 0,
        totalAssetsKept: Int = 0,
        totalSessionsCompleted: Int = 0,
        currentStagedCount: Int = 0
    ) {
        self.totalPhotosDeleted = totalPhotosDeleted
        self.totalVideosDeleted = totalVideosDeleted
        self.totalBytesReclaimed = totalBytesReclaimed
        self.totalAssetsKept = totalAssetsKept
        self.totalSessionsCompleted = totalSessionsCompleted
        self.currentStagedCount = currentStagedCount
    }
}

/// Background `@ModelActor` that executes all SQLite / SwiftData reads and writes off the main thread
/// so 120Hz ProMotion swipe animations never hitch.
@ModelActor
public actor LedgerActor {

    // MARK: - Queries

    /// Returns sets of kept and staged-for-trash asset identifiers.
    public func fetchReviewedIdentifiers() throws -> (kept: Set<String>, stagedTrash: Set<String>) {
        let descriptor = FetchDescriptor<ReviewedAssetRecord>()
        let records = try modelContext.fetch(descriptor)
        var kept = Set<String>()
        var staged = Set<String>()
        for record in records {
            switch record.disposition {
            case .kept:
                kept.insert(record.assetIdentifier)
            case .stagedTrash:
                staged.insert(record.assetIdentifier)
            }
        }
        return (kept, staged)
    }

    /// Loads all currently staged trash items ordered by most recently staged.
    public func fetchStagedTrashItems() throws -> [StagedTrashSnapshot] {
        let stagedRaw = ReviewedAssetRecord.Disposition.stagedTrash.rawValue
        let descriptor = FetchDescriptor<ReviewedAssetRecord>(
            predicate: #Predicate { $0.dispositionRaw == stagedRaw },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let records = try modelContext.fetch(descriptor)
        return records.map { record in
            StagedTrashSnapshot(
                id: record.assetIdentifier,
                fileSizeBytes: record.fileSizeBytes,
                mediaKind: MediaAsset.Kind(rawValue: record.mediaKindRaw) ?? .photo,
                stagedAt: record.updatedAt
            )
        }
    }

    // MARK: - Swipe Mutations

    /// Records an asset as Kept or Staged for Trash.
    public func recordDisposition(
        assetID: String,
        disposition: ReviewedAssetRecord.Disposition,
        fileSizeBytes: Int64,
        mediaKind: MediaAsset.Kind,
        sourceDeckID: String?
    ) throws {
        let descriptor = FetchDescriptor<ReviewedAssetRecord>(
            predicate: #Predicate { $0.assetIdentifier == assetID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.disposition = disposition
            if fileSizeBytes > 0 {
                existing.fileSizeBytes = fileSizeBytes
            }
            existing.mediaKindRaw = mediaKind.rawValue
            existing.sourceDeckID = sourceDeckID
            existing.updatedAt = .now
        } else {
            let record = ReviewedAssetRecord(
                assetIdentifier: assetID,
                disposition: disposition,
                fileSizeBytes: fileSizeBytes,
                mediaKindRaw: mediaKind.rawValue,
                sourceDeckID: sourceDeckID,
                updatedAt: .now
            )
            modelContext.insert(record)
        }

        if disposition == .kept {
            let stats = try fetchOrCreateStatsRecord()
            stats.totalAssetsKept += 1
            stats.lastUpdated = .now
        }

        try modelContext.save()
    }

    /// Removes a disposition record (used when Undoing a Keep or Trash swipe, or rescuing an item).
    public func removeDisposition(assetID: String) throws {
        let descriptor = FetchDescriptor<ReviewedAssetRecord>(
            predicate: #Predicate { $0.assetIdentifier == assetID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    // MARK: - Deck Session Checkpoints

    public func saveDeckCheckpoint(
        deckKey: String,
        orderedAssetIDs: [String],
        currentIndex: Int
    ) throws {
        let descriptor = FetchDescriptor<DeckSessionCheckpoint>(
            predicate: #Predicate { $0.deckKey == deckKey }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.orderedAssetIDs = orderedAssetIDs
            existing.currentIndex = currentIndex
            existing.lastUpdated = .now
        } else {
            let checkpoint = DeckSessionCheckpoint(
                deckKey: deckKey,
                orderedAssetIDs: orderedAssetIDs,
                currentIndex: currentIndex,
                lastUpdated: .now
            )
            modelContext.insert(checkpoint)
        }
        try modelContext.save()
    }

    public func loadDeckCheckpoint(deckKey: String) throws -> (orderedIDs: [String], currentIndex: Int)? {
        let descriptor = FetchDescriptor<DeckSessionCheckpoint>(
            predicate: #Predicate { $0.deckKey == deckKey }
        )
        guard let checkpoint = try modelContext.fetch(descriptor).first else {
            return nil
        }
        return (checkpoint.orderedAssetIDs, checkpoint.currentIndex)
    }

    public func clearDeckCheckpoint(deckKey: String) throws {
        let descriptor = FetchDescriptor<DeckSessionCheckpoint>(
            predicate: #Predicate { $0.deckKey == deckKey }
        )
        if let checkpoint = try modelContext.fetch(descriptor).first {
            modelContext.delete(checkpoint)
            try modelContext.save()
        }
    }

    // MARK: - Batch Deletion Finalization & Lifetime Stats

    /// Called after `PHAssetChangeRequest.deleteAssets` succeeds. Removes deleted records from the staging ledger
    /// and increments `LifetimeStatsRecord`.
    public func finalizeBatchDeletion(deletedItems: [StagedTrashSnapshot]) throws -> LifetimeStatsSnapshot {
        let deletedIDs = Set(deletedItems.map(\.id))
        let descriptor = FetchDescriptor<ReviewedAssetRecord>()
        let allRecords = try modelContext.fetch(descriptor)
        for record in allRecords where deletedIDs.contains(record.assetIdentifier) {
            modelContext.delete(record)
        }

        let stats = try fetchOrCreateStatsRecord()
        var photosCount = 0
        var videosCount = 0
        var bytesCount: Int64 = 0

        for item in deletedItems {
            if item.mediaKind == .video {
                videosCount += 1
            } else {
                photosCount += 1
            }
            bytesCount += item.fileSizeBytes
        }

        stats.totalPhotosDeleted += photosCount
        stats.totalVideosDeleted += videosCount
        stats.totalBytesReclaimed += bytesCount
        stats.totalSessionsCompleted += 1
        stats.lastUpdated = .now

        try modelContext.save()
        return snapshot(from: stats, stagedCount: 0)
    }

    public func fetchLifetimeStats() throws -> LifetimeStatsSnapshot {
        let stats = try fetchOrCreateStatsRecord()
        let stagedRaw = ReviewedAssetRecord.Disposition.stagedTrash.rawValue
        let stagedDescriptor = FetchDescriptor<ReviewedAssetRecord>(
            predicate: #Predicate { $0.dispositionRaw == stagedRaw }
        )
        let stagedCount = (try? modelContext.fetchCount(stagedDescriptor)) ?? 0
        return snapshot(from: stats, stagedCount: stagedCount)
    }

    private func fetchOrCreateStatsRecord() throws -> LifetimeStatsRecord {
        let key = "global_stats"
        let descriptor = FetchDescriptor<LifetimeStatsRecord>(
            predicate: #Predicate { $0.singletonKey == key }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let created = LifetimeStatsRecord(singletonKey: key)
        modelContext.insert(created)
        return created
    }

    private func snapshot(from record: LifetimeStatsRecord, stagedCount: Int) -> LifetimeStatsSnapshot {
        LifetimeStatsSnapshot(
            totalPhotosDeleted: record.totalPhotosDeleted,
            totalVideosDeleted: record.totalVideosDeleted,
            totalBytesReclaimed: record.totalBytesReclaimed,
            totalAssetsKept: record.totalAssetsKept,
            totalSessionsCompleted: record.totalSessionsCompleted,
            currentStagedCount: stagedCount
        )
    }
}
