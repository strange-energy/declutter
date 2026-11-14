import Foundation
import Photos

/// Executes Stage 2 Batch Commit via a single native iOS `PHAssetChangeRequest.deleteAssets` call,
/// moving confirmed items into iOS's 30-day "Recently Deleted" safety net (PRD Section 4.2).
public struct BatchDeleteExecutor: Sendable {
    public enum BatchDeleteError: LocalizedError {
        case noMatchingAssetsFound
        case systemDeletionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noMatchingAssetsFound:
                return "The staged items were already removed from your Photo Library."
            case .systemDeletionFailed(let message):
                return message
            }
        }
    }

    public init() {}

    /// Triggers a single native iOS system confirmation sheet to move all `assetIDs` to "Recently Deleted".
    public func executeBatchDeletion(assetIDs: [String]) async throws {
        guard !assetIDs.isEmpty else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        guard fetchResult.count > 0 else {
            // If assets were already deleted externally in Apple Photos, treat as complete
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    let message = error?.localizedDescription ?? "Deletion was cancelled or declined."
                    continuation.resume(throwing: BatchDeleteError.systemDeletionFailed(message))
                }
            })
        }
    }
}
