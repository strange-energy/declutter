import Foundation
import Photos
import UIKit

/// Zero-latency image/video pre-fetch pipeline using `PHCachingImageManager` (PRD Section 5 & Section 7):
/// - Pre-fetches the next 8 assets in the active stack at screen resolution (`UIScreen.main.bounds.size * scale`).
/// - Never decodes raw 48MP ProRAW buffers into RAM unless the user pinches to zoom past 200%.
/// - Streams uncached iCloud assets (`isNetworkAccessAllowed = true`) while displaying the local thumbnail immediately.
@MainActor
public final class AssetPrefetchPipeline {
    public static let shared = AssetPrefetchPipeline()

    private let cachingManager = PHCachingImageManager()
    private var currentlyCachedIDs: Set<String> = []
    private let lookaheadCount = 8

    /// Target bitmap size capped at device screen pixel resolution.
    public var screenTargetSize: CGSize {
        let bounds = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        return CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    private var defaultCachingOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        return options
    }

    public init() {
        cachingManager.allowsCachingHighQualityImages = true
    }

    /// Updates the sliding lookahead cache window centered at `currentIndex`.
    public func updatePrefetchWindow(deck: [MediaAsset], currentIndex: Int) {
        guard !deck.isEmpty, currentIndex >= 0, currentIndex < deck.count else {
            stopCachingAll()
            return
        }

        let start = currentIndex
        let end = min(deck.count - 1, currentIndex + lookaheadCount)
        let windowSlice = deck[start...end]

        // Pre-warm remote Google Photos assets in the lookahead window
        for asset in windowSlice where asset.isGooglePhotoAsset {
            GooglePhotosCloudService.shared.requestRemoteImage(
                for: asset.id,
                pixelWidth: Int(screenTargetSize.width),
                pixelHeight: Int(screenTargetSize.height)
            ) { _ in }
        }

        let localWindowIDs = Set(windowSlice.filter { !$0.isGooglePhotoAsset }.map(\.id))

        let idsToStart = Array(localWindowIDs.subtracting(currentlyCachedIDs))
        let idsToStop = Array(currentlyCachedIDs.subtracting(localWindowIDs))

        let targetSize = screenTargetSize
        let options = defaultCachingOptions

        if !idsToStop.isEmpty {
            let assetsToStop = fetchPHAssets(withIDs: idsToStop)
            cachingManager.stopCachingImages(
                for: assetsToStop,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            )
        }

        if !idsToStart.isEmpty {
            let assetsToStart = fetchPHAssets(withIDs: idsToStart)
            cachingManager.startCachingImages(
                for: assetsToStart,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            )
        }

        currentlyCachedIDs = localWindowIDs
    }

    public func stopCachingAll() {
        cachingManager.stopCachingImagesForAllAssets()
        currentlyCachedIDs.removeAll()
    }

    /// Requests a display image for a card, calling `onUpdate` first with a fast/opportunistic thumbnail
    /// and then with the screen-resolution image (plus `isInCloud` status for the iCloud spinner).
    @discardableResult
    public func requestCardImage(
        for assetID: String,
        highResolutionForZoom: Bool = false,
        onUpdate: @escaping @MainActor (UIImage?, Bool) -> Void
    ) -> PHImageRequestID? {
        if assetID.hasPrefix("gphoto_") {
            let w = highResolutionForZoom ? 2560 : Int(screenTargetSize.width)
            let h = highResolutionForZoom ? 2560 : Int(screenTargetSize.height)
            GooglePhotosCloudService.shared.requestRemoteImage(for: assetID, pixelWidth: w, pixelHeight: h) { img in
                onUpdate(img, false)
            }
            return nil
        }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let phAsset = fetched.firstObject else {
            onUpdate(nil, false)
            return nil
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = highResolutionForZoom ? .highQualityFormat : .opportunistic
        options.resizeMode = highResolutionForZoom ? .none : .exact

        let targetSize = highResolutionForZoom ? PHImageManagerMaximumSize : screenTargetSize

        return cachingManager.requestImage(
            for: phAsset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
            Task { @MainActor in
                onUpdate(image, isInCloud && isDegraded)
            }
        }
    }

    /// Requests a compact grid thumbnail for the Batch Commit Review Sheet or Dashboard cards.
    @discardableResult
    public func requestThumbnail(
        for assetID: String,
        pointSize: CGSize = CGSize(width: 140, height: 140),
        onResult: @escaping @MainActor (UIImage?) -> Void
    ) -> PHImageRequestID? {
        if assetID.hasPrefix("gphoto_") {
            let scale = Int(UIScreen.main.scale)
            GooglePhotosCloudService.shared.requestRemoteImage(
                for: assetID,
                pixelWidth: Int(pointSize.width) * scale,
                pixelHeight: Int(pointSize.height) * scale
            ) { img in
                onResult(img)
            }
            return nil
        }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let phAsset = fetched.firstObject else {
            onResult(nil)
            return nil
        }

        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return cachingManager.requestImage(
            for: phAsset,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            Task { @MainActor in
                onResult(image)
            }
        }
    }

    /// Requests an `AVPlayerItem` for video playback (PRD Section 7).
    public func requestVideoPlayerItem(
        for assetID: String,
        onResult: @escaping @MainActor (AVPlayerItem?, Bool) -> Void
    ) {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let phAsset = fetched.firstObject, phAsset.mediaType == .video else {
            onResult(nil, false)
            return
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        cachingManager.requestPlayerItem(forVideo: phAsset, options: options) { playerItem, info in
            let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
            Task { @MainActor in
                onResult(playerItem, isInCloud)
            }
        }
    }

    public func cancelRequest(_ requestID: PHImageRequestID?) {
        guard let requestID else { return }
        cachingManager.cancelImageRequest(requestID)
    }

    private func fetchPHAssets(withIDs ids: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
}
