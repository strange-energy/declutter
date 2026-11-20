import Foundation
import UIKit
import WebKit

/// Represents a Google Photos Cloud Album / Folder imported or synced by the user.
public struct GooglePhotosAlbum: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public var mediaItemsCount: Int
    public let coverPhotoBaseUrl: String?
    public let productUrl: String?
    public let isWriteable: Bool

    public init(
        id: String,
        title: String,
        mediaItemsCount: Int,
        coverPhotoBaseUrl: String?,
        productUrl: String? = nil,
        isWriteable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.mediaItemsCount = mediaItemsCount
        self.coverPhotoBaseUrl = coverPhotoBaseUrl
        self.productUrl = productUrl
        self.isWriteable = isWriteable
    }
}

/// Represents a single photo/video extracted from the user's authenticated Google Photos session.
public struct CapturedGooglePhotoItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let baseUrl: String
    public let rawImageUrl: String
    public let productUrl: String?
    public let width: Int
    public let height: Int
    public let isVideo: Bool

    public init(
        id: String,
        baseUrl: String,
        rawImageUrl: String,
        productUrl: String?,
        width: Int = 1080,
        height: Int = 1440,
        isVideo: Bool = false
    ) {
        self.id = id
        self.baseUrl = baseUrl
        self.rawImageUrl = rawImageUrl
        self.productUrl = productUrl
        self.width = width
        self.height = height
        self.isVideo = isVideo
    }
}

/// Consumer-friendly, zero-config Google Photos Cloud Companion service (Milestone 3B):
/// - Zero OAuth Client ID setup required: users sign in directly to their Google Account via an embedded
///   Safari-compatible `WKWebView` session (`GooglePhotosBrowserSheet`), browse or pick any Google Photos folder,
///   and load it directly into SwipeDeck's 120Hz card stack.
/// - Stages left-swiped cloud photos into a dedicated `"To Delete - SwipeDeck"` folder and provides an
///   in-app Guided Deletion Assistant that steps directly through each trashed photo's URL in Google Photos.
@MainActor
@Observable
public final class GooglePhotosCloudService: NSObject {
    public static let shared = GooglePhotosCloudService()

    public static let stagingAlbumID = "to_delete_swipedeck"
    public static let stagingAlbumTitle = "To Delete - SwipeDeck"

    private let connectedKey = "swipedeck.gphotos.is_connected"
    private let connectedEmailKey = "swipedeck.gphotos.user_email"
    private let savedAlbumsKey = "swipedeck.gphotos.saved_albums_v2"
    private let savedItemsByAlbumKey = "swipedeck.gphotos.saved_items_by_album_v2"
    private let stagedTrashItemsKey = "swipedeck.gphotos.staged_trash_items_v2"

    public var isConnected: Bool {
        didSet {
            UserDefaults.standard.set(isConnected, forKey: connectedKey)
        }
    }

    public var connectedEmail: String? {
        didSet {
            UserDefaults.standard.set(connectedEmail, forKey: connectedEmailKey)
        }
    }

    /// All Google Photos folders imported or discovered by the user.
    public private(set) var albums: [GooglePhotosAlbum] = []

    /// Controls presentation of the interactive Google Photos Folder Picker & Deletion Assistant sheet.
    public var isPresentingBrowserSheet = false
    /// When true, opens `GooglePhotosBrowserSheet` directly in Guided Deletion Assistant mode.
    public var launchBrowserInDeletionAssistantMode = false

    /// Cloud items committed to `"To Delete - SwipeDeck"` waiting to be trashed in Google Photos.
    public private(set) var stagedForDeletionItems: [CapturedGooglePhotoItem] = []

    public var statusMessage: String?

    /// Stored items per `albumID` (and `"all"` for the main stream).
    private var itemsByAlbumID: [String: [CapturedGooglePhotoItem]] = [:]
    /// Fast lookup of `asset.id` (`"gphoto_<id>"`) -> `(baseUrl, rawImageUrl)` for `AssetPrefetchPipeline`.
    private var imageURLsByAssetID: [String: (base: String, raw: String)] = [:]
    private var inMemoryImageCache = NSCache<NSString, UIImage>()

    private override init() {
        self.isConnected = UserDefaults.standard.bool(forKey: connectedKey)
        self.connectedEmail = UserDefaults.standard.string(forKey: connectedEmailKey)
        super.init()
        loadPersistedState()
    }

    // MARK: - Importing Folders & Photos from the In-App Google Photos Browser

    /// Imports a folder/album captured from `GooglePhotosBrowserSheet` and returns its `DeckFilter`
    /// so the user can jump straight into swiping it.
    @discardableResult
    public func importCapturedFolder(
        title: String,
        folderURLString: String?,
        items: [CapturedGooglePhotoItem]
    ) -> DeckFilter {
        guard !items.isEmpty else { return .googlePhotosAll }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Google Photos Folder"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Derive a stable album ID from the folder path or title
        let albumID: String
        if let urlStr = folderURLString,
           let range = urlStr.range(of: "/album/") ?? urlStr.range(of: "/share/") {
            let suffix = String(urlStr[range.upperBound...])
                .split(separator: "/")
                .first
                .map(String.init) ?? UUID().uuidString
            albumID = "folder_\(suffix)"
        } else if cleanTitle.lowercased().contains("stream") || cleanTitle.lowercased() == "google photos" {
            albumID = "stream_main"
        } else {
            let slug = cleanTitle.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "_")
            albumID = "folder_\(slug.isEmpty ? "custom" : slug)"
        }

        itemsByAlbumID[albumID] = items

        // Also merge into the aggregate `"all"` stream
        var allItems = itemsByAlbumID["all"] ?? []
        var existingIDs = Set(allItems.map(\.id))
        for item in items where !existingIDs.contains(item.id) {
            allItems.append(item)
            existingIDs.insert(item.id)
        }
        itemsByAlbumID["all"] = allItems

        let coverURL = items.first?.rawImageUrl ?? items.first?.baseUrl
        let album = GooglePhotosAlbum(
            id: albumID,
            title: cleanTitle,
            mediaItemsCount: items.count,
            coverPhotoBaseUrl: coverURL,
            productUrl: folderURLString,
            isWriteable: true
        )

        if let idx = albums.firstIndex(where: { $0.id == albumID }) {
            albums[idx] = album
        } else {
            albums.insert(album, at: 0)
        }

        isConnected = true
        if connectedEmail == nil {
            connectedEmail = "Google Photos Connected"
        }

        rebuildAssetLookupTable()
        persistState()

        Task {
            await syncWebViewCookiesToURLSession()
        }

        return .googlePhotosAlbum(albumID: albumID, title: cleanTitle)
    }

    /// Registers discovered album shells from `https://photos.google.com/albums` so the user sees their folder list.
    public func registerDiscoveredAlbums(_ discovered: [GooglePhotosAlbum]) {
        guard !discovered.isEmpty else { return }
        var changed = false
        for folder in discovered {
            if !albums.contains(where: { $0.id == folder.id || $0.title == folder.title }) {
                albums.append(folder)
                changed = true
            }
        }
        if changed {
            isConnected = true
            rebuildAssetLookupTable()
            persistState()
        }
    }

    /// Instant sample cloud folders so a user can test the Google Photos folder triage flow without logging in.
    public func loadSampleCloudFolders() {
        let sampleFolders: [(id: String, title: String, seeds: [(String, Int, Int)])] = [
            (
                id: "folder_vacation_rome",
                title: "Rome & Amalfi Holiday",
                seeds: [
                    ("https://images.unsplash.com/photo-1552832230-c0197dd311b5?auto=format&fit=crop&w=1080&q=80", 1080, 1440),
                    ("https://images.unsplash.com/photo-1531572753322-ad063cecc140?auto=format&fit=crop&w=1080&q=80", 1080, 1440),
                    ("https://images.unsplash.com/photo-1516483638261-f4dbaf036963?auto=format&fit=crop&w=1080&q=80", 1080, 1440),
                    ("https://images.unsplash.com/photo-1529260830199-42c24126f198?auto=format&fit=crop&w=1080&q=80", 1080, 1440),
                    ("https://images.unsplash.com/photo-1533105079780-92b9be482077?auto=format&fit=crop&w=1080&q=80", 1080, 1440)
                ]
            ),
            (
                id: "folder_food_receipts",
                title: "Receipts & Food Shots",
                seeds: [
                    ("https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=1080&q=80", 1080, 1440),
                    ("https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?auto=format&fit=crop&w=1080&q=80", 1080, 1440),
                    ("https://images.unsplash.com/photo-1482049016688-2d3e1b311543?auto=format&fit=crop&w=1080&q=80", 1080, 1440),
                    ("https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=1080&q=80", 1080, 1440)
                ]
            )
        ]

        var allSampleItems: [CapturedGooglePhotoItem] = []

        for folder in sampleFolders {
            var folderItems: [CapturedGooglePhotoItem] = []
            for (index, seed) in folder.seeds.enumerated() {
                let itemID = "\(folder.id)_item_\(index + 1)"
                let item = CapturedGooglePhotoItem(
                    id: itemID,
                    baseUrl: seed.0,
                    rawImageUrl: seed.0,
                    productUrl: "https://photos.google.com",
                    width: seed.1,
                    height: seed.2,
                    isVideo: false
                )
                folderItems.append(item)
                allSampleItems.append(item)
            }
            itemsByAlbumID[folder.id] = folderItems
            let album = GooglePhotosAlbum(
                id: folder.id,
                title: folder.title,
                mediaItemsCount: folderItems.count,
                coverPhotoBaseUrl: folderItems.first?.rawImageUrl,
                productUrl: "https://photos.google.com/albums",
                isWriteable: true
            )
            if let existingIdx = albums.firstIndex(where: { $0.id == folder.id }) {
                albums[existingIdx] = album
            } else {
                albums.append(album)
            }
        }

        itemsByAlbumID["all"] = allSampleItems
        isConnected = true
        connectedEmail = "Google Photos Cloud"
        rebuildAssetLookupTable()
        persistState()
    }

    public func disconnectAccount() {
        isConnected = false
        connectedEmail = nil
        albums.removeAll()
        itemsByAlbumID.removeAll()
        stagedForDeletionItems.removeAll()
        imageURLsByAssetID.removeAll()
        statusMessage = nil
        persistState()

        // Also clear Google cookies from WKWebsiteDataStore
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let googleRecords = records.filter { $0.displayName.contains("google") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: googleRecords) {}
        }
    }

    public func fetchAlbums() async {
        await syncWebViewCookiesToURLSession()
        rebuildAssetLookupTable()
    }

    // MARK: - Providing MediaAssets to SwipeDeckView

    /// Fetches `MediaAsset` items for a selected Google Photos folder (or `"all"` stream).
    public func fetchMediaAssets(albumID: String?, excludedAssetIDs: Set<String>) async -> [MediaAsset] {
        await syncWebViewCookiesToURLSession()

        let sourceItems: [CapturedGooglePhotoItem]
        if albumID == Self.stagingAlbumID {
            sourceItems = stagedForDeletionItems
        } else if let albumID, let folderItems = itemsByAlbumID[albumID] {
            sourceItems = folderItems
        } else {
            sourceItems = itemsByAlbumID["all"] ?? itemsByAlbumID.values.flatMap { $0 }
        }

        var results: [MediaAsset] = []
        var seen = Set<String>()

        for (index, item) in sourceItems.enumerated() {
            let syntheticID = item.id.hasPrefix("gphoto_") ? item.id : "gphoto_\(item.id)"
            guard !seen.contains(syntheticID) else { continue }
            seen.insert(syntheticID)

            imageURLsByAssetID[syntheticID] = (base: item.baseUrl, raw: item.rawImageUrl)
            if excludedAssetIDs.contains(syntheticID) { continue }

            let estimatedBytes = item.isVideo
                ? Int64(12_500_000)
                : Int64(Double(max(720, item.width) * max(960, item.height)) * 0.24)

            results.append(
                MediaAsset(
                    id: syntheticID,
                    kind: item.isVideo ? .video : .photo,
                    creationDate: Date.now.addingTimeInterval(TimeInterval(-index * 3600)),
                    pixelWidth: item.width,
                    pixelHeight: item.height,
                    duration: 0,
                    isFavorite: false,
                    fileSizeBytes: estimatedBytes,
                    remoteBaseURL: item.baseUrl,
                    remoteProductURL: item.productUrl,
                    googleMediaItemID: item.id
                )
            )
        }
        return results
    }

    // MARK: - Deletion & "To Delete - SwipeDeck" Folder Staging

    /// Moves committed cloud trash items into the `"To Delete - SwipeDeck"` folder and removes them from their active SwipeDeck folder.
    /// Also prepares them for the Guided Deletion Assistant in `GooglePhotosBrowserSheet`.
    public func commitCloudTrashItems(assetIDs: [String]) async throws -> URL? {
        let normalizedIDs = Set(assetIDs.map { $0.replacingOccurrences(of: "gphoto_", with: "") })
        let fullIDs = Set(assetIDs)

        let allKnownItems = itemsByAlbumID.values.flatMap { $0 }
        var newlyStaged: [CapturedGooglePhotoItem] = []
        var existingStagedIDs = Set(stagedForDeletionItems.map(\.id))

        for item in allKnownItems {
            if normalizedIDs.contains(item.id) || fullIDs.contains(item.id) || fullIDs.contains("gphoto_\(item.id)") {
                if !existingStagedIDs.contains(item.id) {
                    newlyStaged.append(item)
                    existingStagedIDs.insert(item.id)
                }
            }
        }

        stagedForDeletionItems.insert(contentsOf: newlyStaged, at: 0)

        // Remove committed items from source folders so the folder reflects the cleaned state
        for (folderKey, folderItems) in itemsByAlbumID where folderKey != Self.stagingAlbumID {
            let filtered = folderItems.filter {
                !normalizedIDs.contains($0.id) && !fullIDs.contains($0.id) && !fullIDs.contains("gphoto_\($0.id)")
            }
            itemsByAlbumID[folderKey] = filtered
        }

        // Update album counts and ensure the `"To Delete - SwipeDeck"` folder appears in the user's Google Photos folder list
        for idx in albums.indices where albums[idx].id != Self.stagingAlbumID {
            if let count = itemsByAlbumID[albums[idx].id]?.count {
                albums[idx].mediaItemsCount = count
            }
        }

        updateStagingAlbumCard()
        rebuildAssetLookupTable()
        persistState()

        if let firstURLStr = stagedForDeletionItems.first?.productUrl,
           let url = URL(string: firstURLStr) {
            return url
        }
        return URL(string: "https://photos.google.com")
    }

    public func clearStagedForDeletionItems() {
        stagedForDeletionItems.removeAll()
        albums.removeAll { $0.id == Self.stagingAlbumID }
        itemsByAlbumID.removeValue(forKey: Self.stagingAlbumID)
        persistState()
    }

    public func removeSingleStagedDeletionItem(id: String) {
        stagedForDeletionItems.removeAll { $0.id == id }
        updateStagingAlbumCard()
        persistState()
    }

    private func updateStagingAlbumCard() {
        if stagedForDeletionItems.isEmpty {
            albums.removeAll { $0.id == Self.stagingAlbumID }
            itemsByAlbumID.removeValue(forKey: Self.stagingAlbumID)
        } else {
            itemsByAlbumID[Self.stagingAlbumID] = stagedForDeletionItems
            let stagingAlbum = GooglePhotosAlbum(
                id: Self.stagingAlbumID,
                title: Self.stagingAlbumTitle,
                mediaItemsCount: stagedForDeletionItems.count,
                coverPhotoBaseUrl: stagedForDeletionItems.first?.rawImageUrl,
                productUrl: stagedForDeletionItems.first?.productUrl,
                isWriteable: true
            )
            if let idx = albums.firstIndex(where: { $0.id == Self.stagingAlbumID }) {
                albums[idx] = stagingAlbum
            } else {
                albums.insert(stagingAlbum, at: 0)
            }
        }
    }

    // MARK: - Authenticated Remote Image Loading

    public func requestRemoteImage(
        for assetID: String,
        pixelWidth: Int = 1080,
        pixelHeight: Int = 1920,
        onResult: @escaping @MainActor (UIImage?) -> Void
    ) {
        let cacheKey = "\(assetID)_\(pixelWidth)x\(pixelHeight)" as NSString
        if let cached = inMemoryImageCache.object(forKey: cacheKey) {
            onResult(cached)
            return
        }

        guard let urls = imageURLsByAssetID[assetID] else {
            onResult(nil)
            return
        }

        let targetW = max(300, min(pixelWidth, 1600))
        let targetH = max(300, min(pixelHeight, 2000))

        // Build high-res candidate URL for Google userdata URLs (`lh3.googleusercontent.com`)
        let candidateURLStrings: [String]
        if urls.base.contains("googleusercontent.com") && !urls.base.contains("?") {
            candidateURLStrings = [
                "\(urls.base)=w\(targetW)-h\(targetH)",
                urls.raw,
                urls.base
            ]
        } else {
            candidateURLStrings = [urls.raw, urls.base]
        }

        Task {
            await syncWebViewCookiesToURLSession()

            for urlStr in candidateURLStrings {
                guard let url = URL(string: urlStr) else { continue }
                do {
                    var request = URLRequest(url: url)
                    request.setValue(
                        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                        forHTTPHeaderField: "User-Agent"
                    )
                    let (data, _) = try await URLSession.shared.data(for: request)
                    if let image = UIImage(data: data) {
                        self.inMemoryImageCache.setObject(image, forKey: cacheKey)
                        onResult(image)
                        return
                    }
                } catch {
                    continue
                }
            }
            onResult(nil)
        }
    }

    /// Copies authenticated Google session cookies from `WKWebsiteDataStore.default()` into `HTTPCookieStorage.shared`
    /// so `URLSession.shared` can load private `lh3.googleusercontent.com` photos directly.
    public func syncWebViewCookiesToURLSession() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        for cookie in cookies where cookie.domain.contains("google") {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    // MARK: - Persistence & Lookup Table

    private func rebuildAssetLookupTable() {
        for album in albums {
            if let cover = album.coverPhotoBaseUrl {
                imageURLsByAssetID["gphoto_cover_\(album.id)"] = (base: cover, raw: cover)
            }
        }
        for items in itemsByAlbumID.values {
            for item in items {
                let syntheticID = item.id.hasPrefix("gphoto_") ? item.id : "gphoto_\(item.id)"
                imageURLsByAssetID[syntheticID] = (base: item.baseUrl, raw: item.rawImageUrl)
            }
        }
        for item in stagedForDeletionItems {
            let syntheticID = item.id.hasPrefix("gphoto_") ? item.id : "gphoto_\(item.id)"
            imageURLsByAssetID[syntheticID] = (base: item.baseUrl, raw: item.rawImageUrl)
        }
    }

    private func persistState() {
        if let encodedAlbums = try? JSONEncoder().encode(albums) {
            UserDefaults.standard.set(encodedAlbums, forKey: savedAlbumsKey)
        }
        if let encodedItems = try? JSONEncoder().encode(itemsByAlbumID) {
            UserDefaults.standard.set(encodedItems, forKey: savedItemsByAlbumKey)
        }
        if let encodedStaged = try? JSONEncoder().encode(stagedForDeletionItems) {
            UserDefaults.standard.set(encodedStaged, forKey: stagedTrashItemsKey)
        }
    }

    private func loadPersistedState() {
        if let data = UserDefaults.standard.data(forKey: savedAlbumsKey),
           let decoded = try? JSONDecoder().decode([GooglePhotosAlbum].self, from: data) {
            self.albums = decoded
        }
        if let data = UserDefaults.standard.data(forKey: savedItemsByAlbumKey),
           let decoded = try? JSONDecoder().decode([String: [CapturedGooglePhotoItem]].self, from: data) {
            self.itemsByAlbumID = decoded
        }
        if let data = UserDefaults.standard.data(forKey: stagedTrashItemsKey),
           let decoded = try? JSONDecoder().decode([CapturedGooglePhotoItem].self, from: data) {
            self.stagedForDeletionItems = decoded
        }
        rebuildAssetLookupTable()
    }
}
