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

        let exif = await Self.readEXIFProperties(for: phAsset)

        let metadata = AssetMetadata(
            assetID: asset.id,
            filename: filename,
            fileSizeBytes: bytes,
            creationDate: phAsset.creationDate,
            dimensions: "\(phAsset.pixelWidth) × \(phAsset.pixelHeight) (\(asset.megapixelsText))",
            cameraModel: exif.cameraModel,
            lensModel: exif.lensModel,
            iso: exif.iso,
            shutterSpeed: exif.shutterSpeed,
            aperture: exif.aperture,
            focalLength: exif.focalLength,
            locationName: locationString,
            isStoredIniCloud: exif.isIniCloud
        )

        metadataCache[asset.id] = metadata
        return metadata
    }

    private struct EXIFSnapshot: Sendable {
        var cameraModel: String?
        var lensModel: String?
        var iso: Int?
        var shutterSpeed: String?
        var aperture: String?
        var focalLength: String?
        var isIniCloud: Bool = false
    }

    private static func readEXIFProperties(for phAsset: PHAsset) async -> EXIFSnapshot {
        guard phAsset.mediaType == .image else {
            return EXIFSnapshot()
        }

        return await withCheckedContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = false

            phAsset.requestContentEditingInput(with: options) { input, info in
                var snapshot = EXIFSnapshot()
                let isIniCloud = (info[PHContentEditingInputResultIsInCloudKey] as? Bool) ?? false
                snapshot.isIniCloud = isIniCloud

                if let url = input?.fullSizeImageURL,
                   let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {

                    if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                        snapshot.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
                    }

                    if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                        snapshot.lensModel = exif[kCGImagePropertyExifLensModel] as? String
                        if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let firstISO = isoArray.first {
                            snapshot.iso = firstISO
                        }
                        if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double {
                            snapshot.aperture = String(format: "%.1f", fNumber)
                        }
                        if let focal = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int {
                            snapshot.focalLength = "\(focal)mm"
                        } else if let focalRaw = exif[kCGImagePropertyExifFocalLength] as? Double {
                            snapshot.focalLength = String(format: "%.0fmm", focalRaw)
                        }
                        if let exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double, exposureTime > 0 {
                            if exposureTime >= 1.0 {
                                snapshot.shutterSpeed = String(format: "%.1f", exposureTime)
                            } else {
                                let denominator = Int((1.0 / exposureTime).rounded())
                                snapshot.shutterSpeed = "1/\(max(1, denominator))"
                            }
                        }
                    }
                }
                continuation.resume(returning: snapshot)
            }
        }
    }
}
