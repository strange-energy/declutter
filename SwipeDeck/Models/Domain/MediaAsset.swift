import Foundation
import Photos

/// Lightweight Sendable value type representing a photo, Live Photo, or video in the active triage deck.
public struct MediaAsset: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case photo
        case livePhoto
        case video
    }

    /// The `PHAsset.localIdentifier` (or Google Photos mediaItem ID in Secondary Cloud Companion Mode).
    public let id: String
    public let kind: Kind
    public let creationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let duration: TimeInterval
    public let isFavorite: Bool
    /// Estimated or extracted byte size on disk (`PHAssetResource`).
    public var fileSizeBytes: Int64

    public init(
        id: String,
        kind: Kind,
        creationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        duration: TimeInterval = 0,
        isFavorite: Bool = false,
        fileSizeBytes: Int64 = 0
    ) {
        self.id = id
        self.kind = kind
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.isFavorite = isFavorite
        self.fileSizeBytes = fileSizeBytes
    }

    public init(phAsset: PHAsset, estimatedBytes: Int64 = 0) {
        self.id = phAsset.localIdentifier
        if phAsset.mediaType == .video {
            self.kind = .video
        } else if phAsset.mediaSubtypes.contains(.photoLive) {
            self.kind = .livePhoto
        } else {
            self.kind = .photo
        }
        self.creationDate = phAsset.creationDate
        self.pixelWidth = phAsset.pixelWidth
        self.pixelHeight = phAsset.pixelHeight
        self.duration = phAsset.duration
        self.isFavorite = phAsset.isFavorite
        self.fileSizeBytes = estimatedBytes
    }

    public var resolutionText: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    public var megapixelsText: String {
        let mp = Double(pixelWidth * pixelHeight) / 1_000_000.0
        return String(format: "%.1f MP", mp)
    }

    public var formattedDuration: String? {
        guard kind == .video, duration > 0 else { return nil }
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
