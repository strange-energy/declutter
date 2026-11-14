import Foundation
import SwiftData

/// Stores lifetime decluttering telemetry: total photos/videos deleted, bytes freed, and sessions completed.
@Model
public final class LifetimeStatsRecord {
    @Attribute(.unique)
    public var singletonKey: String
    public var totalPhotosDeleted: Int
    public var totalVideosDeleted: Int
    public var totalBytesReclaimed: Int64
    public var totalAssetsKept: Int
    public var totalSessionsCompleted: Int
    public var lastUpdated: Date

    public init(
        singletonKey: String = "global_stats",
        totalPhotosDeleted: Int = 0,
        totalVideosDeleted: Int = 0,
        totalBytesReclaimed: Int64 = 0,
        totalAssetsKept: Int = 0,
        totalSessionsCompleted: Int = 0,
        lastUpdated: Date = .now
    ) {
        self.singletonKey = singletonKey
        self.totalPhotosDeleted = totalPhotosDeleted
        self.totalVideosDeleted = totalVideosDeleted
        self.totalBytesReclaimed = totalBytesReclaimed
        self.totalAssetsKept = totalAssetsKept
        self.totalSessionsCompleted = totalSessionsCompleted
        self.lastUpdated = lastUpdated
    }
}
