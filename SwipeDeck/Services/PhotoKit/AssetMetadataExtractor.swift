import Foundation
import Photos
import ImageIO
import CoreLocation

/// Thread-safe actor that extracts file size in bytes (`PHAssetResource`) and rich EXIF/camera metadata
/// without blocking the main thread. Caches byte sizes in memory for instant Trash Pill calculations.
public actor AssetMetadataExtractor {
    public static let shared = AssetMetadataExtractor()

    private var byteSizeCache: [String: Int64] = [:]
    private var metadataCache: [String: AssetMetadata] = [:]

    public init() {}

    /// Returns the primary resource file size in bytes for a `PHAsset`.
    public func fileSizeBytes(for assetID: String) -> Int64 {
        if let cached = byteSizeCache[assetID] {
            return cached
        }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let phAsset = fetchResult.firstObject else { return 0 }
        let size = Self.extractPrimaryByteSize(for: phAsset)
        byteSizeCache[assetID] = size
        return size
    }

    /// Synchronous helper for background batch sorting (e.g., Heavy Hitters sieve).
    public nonisolated static func extractPrimaryByteSize(for phAsset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: phAsset)
        guard let primary = resources.first(where: {
            $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto || $0.type == .fullSizeVideo
        }) ?? resources.first else {
            return 0
        }
        if let sizeNumber = primary.value(forKey: "fileSize") as? CLong {
            return Int64(sizeNumber)
        }
        if let sizeInt64 = primary.value(forKey: "fileSize") as? Int64 {
            return sizeInt64
        }
        return 0
    }

    /// Extracts full EXIF / technical metadata when the user taps a card to toggle the Metadata Overlay (PRD Section 3.1).
    public func extractMetadata(for asset: MediaAsset) async -> AssetMetadata {
        if let cached = metadataCache[asset.id] {
            return cached
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            return AssetMetadata(
                assetID: asset.id,
                fileSizeBytes: asset.fileSizeBytes,
                creationDate: asset.creationDate,
                dimensions: asset.resolutionText
            )
        }

        let resources = PHAssetResource.assetResources(for: phAsset)
        let primaryResource = resources.first
        let filename = primaryResource?.originalFilename ?? "IMG_ASSET"
        let bytes = byteSizeCache[asset.id] ?? Self.extractPrimaryByteSize(for: phAsset)
        byteSizeCache[asset.id] = bytes

        let locationString: String?
        if let coord = phAsset.location?.coordinate {
            locationString = String(format: "%.4f°, %.4f°", coord.latitude, coord.longitude)
        } else {
            locationString = nil
        }

        let metadata = AssetMetadata(
            assetID: asset.id,
            filename: filename,
            fileSizeBytes: bytes,
            creationDate: phAsset.creationDate,
            dimensions: "\(phAsset.pixelWidth) × \(phAsset.pixelHeight) (\(asset.megapixelsText))",
            cameraModel: phAsset.mediaSubtypes.contains(.photoScreenshot) ? "Screenshot" : "iPhone Camera",
            lensModel: phAsset.mediaSubtypes.contains(.photoLive) ? "Live Photo" : nil,
            iso: nil,
            shutterSpeed: nil,
            aperture: nil,
            focalLength: nil,
            locationName: locationString,
            isStoredIniCloud: false
        )

        metadataCache[asset.id] = metadata
        return metadata
    }
}
