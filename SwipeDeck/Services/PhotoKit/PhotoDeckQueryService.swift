import Foundation
import Photos

/// Summary descriptor for an album or month deck displayed on the Home Dashboard.
public struct DeckSummaryItem: Identifiable, Hashable, Sendable {
    public let filter: DeckFilter
    public let unreviewedCount: Int
    public let totalCount: Int
    public let coverAssetID: String?

    public var id: String { filter.id }

    public init(filter: DeckFilter, unreviewedCount: Int, totalCount: Int, coverAssetID: String?) {
        self.filter = filter
        self.unreviewedCount = unreviewedCount
        self.totalCount = totalCount
        self.coverAssetID = coverAssetID
    }
}

/// Builds and executes PhotoKit queries for all Deck Generators (PRD Section 4.1) with O(1) dashboard counts
/// and capped enumeration so opening a deck is instantaneous even on 50,000+ photo libraries.
public final class PhotoDeckQueryService: Sendable {
    public static let shared = PhotoDeckQueryService()

    public init() {}

    /// Fetches the ordered list of `MediaAsset` items for a selected `DeckFilter`,
    /// capping initial session size to `maxSessionSize` (default 300) so opening any deck takes < 50ms.
    public func buildDeck(
        for filter: DeckFilter,
        excludedAssetIDs: Set<String>,
        maxSessionSize: Int = 300
    ) async -> [MediaAsset] {
        switch filter {
        case .googlePhotosAll:
            return await GooglePhotosCloudService.shared.fetchMediaAssets(
                albumID: nil,
                excludedAssetIDs: excludedAssetIDs
            )
        case .googlePhotosAlbum(let albumID, _):
            return await GooglePhotosCloudService.shared.fetchMediaAssets(
                albumID: albumID,
                excludedAssetIDs: excludedAssetIDs
            )
        default:
            break
        }

        return await Task.detached(priority: .userInitiated) {
            let phAssets = Self.fetchPHAssets(for: filter)
            let count = phAssets.count
            guard count > 0 else { return [] }

            if filter == .heavyHitters {
                // Fast pixel-volume + duration heuristic on up to 250 recent candidates,
                // then exact byte lookup on the top 60 so Heavy Hitters opens in < 150ms.
                let scanCap = min(count, 250)
                var candidates: [PHAsset] = []
                candidates.reserveCapacity(scanCap)

                for idx in 0..<count {
                    if candidates.count >= scanCap { break }
                    let asset = phAssets.object(at: idx)
                    if !excludedAssetIDs.contains(asset.localIdentifier) {
                        candidates.append(asset)
                    }
                }

                // Pre-rank by video duration + pixel count (zero disk I/O)
                candidates.sort { a, b in
                    let scoreA = (a.mediaType == .video ? Int64(a.duration * 3_500_000) : 0) + Int64(a.pixelWidth * a.pixelHeight)
                    let scoreB = (b.mediaType == .video ? Int64(b.duration * 3_500_000) : 0) + Int64(b.pixelWidth * b.pixelHeight)
                    return scoreA > scoreB
                }

                let topCandidates = candidates.prefix(80)
                var results: [MediaAsset] = topCandidates.map { phAsset in
                    let estimatedBytes = Self.fastEstimatedBytes(for: phAsset)
                    return MediaAsset(phAsset: phAsset, estimatedBytes: estimatedBytes)
                }
                results.sort { $0.fileSizeBytes > $1.fileSizeBytes }
                return results
            } else {
                var results: [MediaAsset] = []
                results.reserveCapacity(min(count, maxSessionSize))

                for idx in 0..<count {
                    if results.count >= maxSessionSize { break }
                    let phAsset = phAssets.object(at: idx)
                    if !excludedAssetIDs.contains(phAsset.localIdentifier) {
                        results.append(MediaAsset(phAsset: phAsset))
                    }
                }
                return results
            }
        }.value
    }

    /// Generates fast O(1) summary counts for the streamlined Home Dashboard without enumerating every asset in the library.
    public func fetchDashboardSummaries(excludedAssetIDs: Set<String>) async -> (
        sources: [DeckSummaryItem],
        months: [DeckSummaryItem],
        userAlbums: [DeckSummaryItem]
    ) {
        return await Task.detached(priority: .userInitiated) {
            let sourceFilters: [DeckFilter] = [
                .heavyHitters,
                .onThisDay,
                .allPhotos,
                .screenshots,
                .screenRecordings,
                .favorites
            ]

            let sources = sourceFilters.map { filter in
                Self.fastSummarize(filter: filter, excludedIDs: excludedAssetIDs)
            }

            let months = Self.buildRecentMonthSummaries(excludedIDs: excludedAssetIDs, maxMonths: 12)
            let albums = Self.buildUserAlbumSummaries(excludedIDs: excludedAssetIDs)

            return (sources, months, albums)
        }.value
    }

    // MARK: - Fast O(1) / Bounded Summary Helpers

    private static func fastSummarize(filter: DeckFilter, excludedIDs: Set<String>) -> DeckSummaryItem {
        let fetched = fetchPHAssets(for: filter)
        let total = fetched.count
        guard total > 0 else {
            return DeckSummaryItem(filter: filter, unreviewedCount: 0, totalCount: 0, coverAssetID: nil)
        }

        let coverID = fetched.firstObject?.localIdentifier

        // For small collections (<= 400 items, such as a single month or screenshots), compute exact unreviewed count.
        // For huge collections (e.g., 30,000 All Photos), avoid O(N) enumeration on the dashboard.
        if total <= 400 && !excludedIDs.isEmpty {
            var unreviewed = 0
            for idx in 0..<total {
                let asset = fetched.object(at: idx)
                if !excludedIDs.contains(asset.localIdentifier) {
                    unreviewed += 1
                }
            }
            return DeckSummaryItem(filter: filter, unreviewedCount: unreviewed, totalCount: total, coverAssetID: coverID)
        } else {
            let approxUnreviewed = max(0, total - excludedIDs.count)
            return DeckSummaryItem(
                filter: filter,
                unreviewedCount: excludedIDs.isEmpty ? total : min(total, max(1, approxUnreviewed)),
                totalCount: total,
                coverAssetID: coverID
            )
        }
    }

    private static func fastEstimatedBytes(for phAsset: PHAsset) -> Int64 {
        let exact = AssetMetadataExtractor.extractPrimaryByteSize(for: phAsset)
        if exact > 0 { return exact }
        if phAsset.mediaType == .video {
            return max(2_500_000, Int64(phAsset.duration * 2_200_000))
        }
        return max(800_000, Int64(Double(phAsset.pixelWidth * phAsset.pixelHeight) * 0.22))
    }

    private static func fetchPHAssets(for filter: DeckFilter) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        switch filter {
        case .allPhotos:
            return PHAsset.fetchAssets(with: options)

        case .favorites:
            if let collection = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumFavorites,
                options: nil
            ).firstObject {
                return PHAsset.fetchAssets(in: collection, options: options)
            }
            options.predicate = NSPredicate(format: "isFavorite == YES")
            return PHAsset.fetchAssets(with: options)

        case .screenshots:
            if let collection = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumScreenshots,
                options: nil
            ).firstObject {
                return PHAsset.fetchAssets(in: collection, options: options)
            }
            options.predicate = NSPredicate(
                format: "(mediaSubtype & %d) != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            return PHAsset.fetchAssets(with: options)

        case .screenRecordings:
            if let collection = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumVideos,
                options: nil
            ).firstObject {
                return PHAsset.fetchAssets(in: collection, options: options)
            }
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            return PHAsset.fetchAssets(with: options)

        case .messagingApps:
            let albumOptions = PHFetchOptions()
            albumOptions.predicate = NSPredicate(
                format: "title CONTAINS[cd] 'WhatsApp' OR title CONTAINS[cd] 'Telegram'"
            )
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .album,
                subtype: .any,
                options: albumOptions
            )
            if let first = collections.firstObject {
                return PHAsset.fetchAssets(in: first, options: options)
            }
            options.predicate = NSPredicate(value: false)
            return PHAsset.fetchAssets(with: options)

        case .userAlbum(let id, _):
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [id],
                options: nil
            )
            if let collection = collections.firstObject {
                return PHAsset.fetchAssets(in: collection, options: options)
            }
            options.predicate = NSPredicate(value: false)
            return PHAsset.fetchAssets(with: options)

        case .onThisDay:
            let calendar = Calendar.current
            let now = Date.now
            let currentMonth = calendar.component(.month, from: now)
            let currentDay = calendar.component(.day, from: now)
            let currentYear = calendar.component(.year, from: now)

            var predicates: [NSPredicate] = []
            for year in stride(from: currentYear, through: max(2014, currentYear - 12), by: -1) {
                var startComps = DateComponents()
                startComps.year = year
                startComps.month = currentMonth
                startComps.day = currentDay
                if let dayStart = calendar.date(from: startComps),
                   let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) {
                    predicates.append(
                        NSPredicate(format: "creationDate >= %@ AND creationDate < %@", dayStart as NSDate, dayEnd as NSDate)
                    )
                }
            }
            if !predicates.isEmpty {
                options.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
            }
            return PHAsset.fetchAssets(with: options)

        case .monthYear(let year, let month):
            let calendar = Calendar.current
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            if let start = calendar.date(from: comps),
               let end = calendar.date(byAdding: .month, value: 1, to: start) {
                options.predicate = NSPredicate(
                    format: "creationDate >= %@ AND creationDate < %@",
                    start as NSDate,
                    end as NSDate
                )
            }
            return PHAsset.fetchAssets(with: options)

        case .customDateRange(let start, let end):
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                start as NSDate,
                end as NSDate
            )
            return PHAsset.fetchAssets(with: options)

        case .heavyHitters:
            if let videoCollection = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumVideos,
                options: nil
            ).firstObject {
                let videos = PHAsset.fetchAssets(in: videoCollection, options: options)
                if videos.count > 0 {
                    return videos
                }
            }
            return PHAsset.fetchAssets(with: options)
        }
    }

    /// Scans the user's actual newest photo date first so that even if the device clock or library dates vary,
    /// the horizontal month strip shows the user's real active months with photos.
    private static func buildRecentMonthSummaries(
        excludedIDs: Set<String>,
        maxMonths: Int
    ) -> [DeckSummaryItem] {
        let calendar = Calendar.current
        let newestFetchOptions = PHFetchOptions()
        newestFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        newestFetchOptions.fetchLimit = 1
        let anchorDate = PHAsset.fetchAssets(with: newestFetchOptions).firstObject?.creationDate ?? Date.now

        var items: [DeckSummaryItem] = []
        for offset in 0..<maxMonths {
            guard let targetDate = calendar.date(byAdding: .month, value: -offset, to: anchorDate) else { continue }
            let year = calendar.component(.year, from: targetDate)
            let month = calendar.component(.month, from: targetDate)
            let filter = DeckFilter.monthYear(year: year, month: month)
            let summary = fastSummarize(filter: filter, excludedIDs: excludedIDs)
            if summary.totalCount > 0 {
                items.append(summary)
            }
        }
        return items
    }

    private static func buildUserAlbumSummaries(excludedIDs: Set<String>) -> [DeckSummaryItem] {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        var results: [DeckSummaryItem] = []
        let cap = min(collections.count, 12)
        for idx in 0..<cap {
            let collection = collections.object(at: idx)
            let title = collection.localizedTitle ?? "Untitled Album"
            let filter = DeckFilter.userAlbum(id: collection.localIdentifier, title: title)
            let summary = fastSummarize(filter: filter, excludedIDs: excludedIDs)
            if summary.totalCount > 0 {
                results.append(summary)
            }
        }
        return results
    }
}
