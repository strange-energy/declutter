import Foundation
import SwiftData

/// Tracks every `localIdentifier` marked as Kept or Staged for Deletion (PRD Section 4.2 & 4.3).
@Model
public final class ReviewedAssetRecord {
    public enum Disposition: String, Codable, Sendable {
        case kept
        case stagedTrash
    }

    @Attribute(.unique)
    public var assetIdentifier: String
    public var dispositionRaw: String
    public var fileSizeBytes: Int64
    public var mediaKindRaw: String
    public var sourceDeckID: String?
    public var updatedAt: Date

    public var disposition: Disposition {
        get { Disposition(rawValue: dispositionRaw) ?? .kept }
        set { dispositionRaw = newValue.rawValue }
    }

    public init(
        assetIdentifier: String,
        disposition: Disposition,
        fileSizeBytes: Int64,
        mediaKindRaw: String = MediaAsset.Kind.photo.rawValue,
        sourceDeckID: String? = nil,
        updatedAt: Date = .now
    ) {
        self.assetIdentifier = assetIdentifier
        self.dispositionRaw = disposition.rawValue
        self.fileSizeBytes = fileSizeBytes
        self.mediaKindRaw = mediaKindRaw
        self.sourceDeckID = sourceDeckID
        self.updatedAt = updatedAt
    }
}
