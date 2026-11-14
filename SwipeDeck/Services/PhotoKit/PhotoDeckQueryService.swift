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

/// Builds and executes PhotoKit queries for all Deck Generators (PRD Section 4.1):
/// - By Source: All Photos, Favorites, Screenshots, Screen Recordings, WhatsApp/Telegram, User Albums
/// - By Timeframe: On This Day, Month/Year buckets, Custom Date Range
/// - Smart Storage Sieves: Heavy Hitters (largest videos & photos first)
public final class PhotoDeckQueryService: Sendable {
    public static let shared = PhotoDeckQueryService()

    public init() {}

    /// Fetches the ordered list of `MediaAsset` items for a selected `DeckFilter`,
    /// automatically filtering out previously kept and staged-for-trash assets unless `includeKept` is true.
    public func buildDeck(
        for filter: DeckFilter,
        excludedAssetIDs: Set<String>,
        maxHeavyHitterScanLimit: Int = 600
    ) async -> [MediaAsset] {
        return await Task.detached(priority: .userInitiated) {
            let phAssets = Self.fetchPHAssets(for: filter)
            var results: [MediaAsset] = []
            results.reserveCapacity(min(phAssets.count, 500))

            if filter == .heavyHitters {
                // Scan candidate assets and rank by byte size descending (PRD Section 4.1)
                let scanCap = min(phAssets.count, maxHeavyHitterScanLimit)
                var sizedCandidates: [MediaAsset] = []
                sizedCandidates.reserveCapacity(scanCap)

                for idx in 0..<scanCap {
                    let phAsset = phAssets.object(at: idx)
                    if excludedAssetIDs.contains(phAsset.localIdentifier) { continue }
                    let bytes = AssetMetadataExtractor.extractPrimaryByteSize(for: phAsset)
                    sizedCandidates.append(MediaAsset(phAsset: phAsset, estimatedBytes: bytes))
                }

                sizedCandidates.sort { $0.fileSizeBytes > $1.fileSizeBytes }
                return sizedCandidates
            } else {
                phAssets.enumerateObjects { phAsset, _, _ in
                    if !excludedAssetIDs.contains(phAsset.localIdentifier) {
                        results.append(MediaAsset(phAsset: phAsset))
                    }
                }
                return results
            }
        }.value
    }

    /// Generates summary counts for the standard Source & Smart Sieve decks on the Home Dashboard.
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
                .favorites,
                .messagingApps
            ]

            let sources = sourceFilters.map { filter in
                Self.summarize(filter: filter, excludedIDs: excludedAssetIDs)
            }

            let months = Self.buildRecentMonthSummaries(excludedIDs: excludedAssetIDs, maxMonths: 12)
            let albums = Self.buildUserAlbumSummaries(excludedIDs: excludedAssetIDs)

            return (sources, months, albums)
        }.value
    }

    // MARK: - Internal PhotoKit Fetch Builders

    private static func summarize(filter: DeckFilter, excludedIDs: Set<String>) -> DeckSummaryItem {
        let fetched = fetchPHAssets(for: filter)
        let total = fetched.count
        var unreviewed = 0
        var coverID: String?

        fetched.enumerateObjects { asset, _, _ in
            if coverID == nil {
                coverID = asset.localIdentifier
            }
            if !excludedIDs.contains(asset.localIdentifier) {
                unreviewed += 1
            }
        }

        return DeckSummaryItem(
            filter: filter,
            unreviewedCount: unreviewed,
            totalCount: total,
            coverAssetID: coverID
        )
    }

    private static func fetchPHAssets(for filter: DeckFilter) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        switch filter {
        case .allPhotos:
            return PHAsset.fetchAssets(with: options)

        case .favorites:
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
            // Screen recordings are videos captured on device screen
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            return PHAsset.fetchAssets(with: options)

        case .messagingApps:
            // Look for WhatsApp / Telegram albums; fallback to empty fetch if none exist yet
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
            for year in stride(from: currentYear, through: max(2007, currentYear - 20), by: -1) {
                var startComps = DateComponents()
                startComps.year = year
                startComps.month = currentMonth
                startComps.day = currentDay
                startComps.hour = 0
                startComps.minute = 0
                startComps.second = 0

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
            // Prioritize videos and high-res photos for storage recovery
            return PHAsset.fetchAssets(with: options)
        }
    }

    private static func buildRecentMonthSummaries(
        excludedIDs: Set<String>,
        maxMonths: Int
    ) -> [DeckSummaryItem] {
        let calendar = Calendar.current
        let now = Date.now
        var items: [DeckSummaryItem] = []

        for offset in 0..<maxMonths {
            guard let targetDate = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let year = calendar.component(.year, from: targetDate)
            let month = calendar.component(.month, from: targetDate)
            let filter = DeckFilter.monthYear(year: year, month: month)
            let summary = summarize(filter: filter, excludedIDs: excludedIDs)
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
        collections.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle ?? "Untitled Album"
            let filter = DeckFilter.userAlbum(id: collection.localIdentifier, title: title)
            let summary = summarize(filter: filter, excludedIDs: excludedIDs)
            if summary.totalCount > 0 {
                results.append(summary)
            }
        }
        return results
    }
}
