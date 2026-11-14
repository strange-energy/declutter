import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Represents a Google Photos Cloud Album / Folder.
public struct GooglePhotosAlbum: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let mediaItemsCount: Int
    public let coverPhotoBaseUrl: String?
    public let productUrl: String?
    public let isWriteable: Bool

    public init(
        id: String,
        title: String,
        mediaItemsCount: Int,
        coverPhotoBaseUrl: String?,
        productUrl: String? = nil,
        isWriteable: Bool = false
    ) {
        self.id = id
        self.title = title
        self.mediaItemsCount = mediaItemsCount
        self.coverPhotoBaseUrl = coverPhotoBaseUrl
        self.productUrl = productUrl
        self.isWriteable = isWriteable
    }
}

/// Optional, non-intrusive Google Photos Cloud Companion service (PRD Section 2 & Milestone 3B):
/// - Authenticates via PKCE OAuth 2.0 (`ASWebAuthenticationSession`) only if the user chooses to connect.
/// - Lists Google Photos folders/albums so the user can point to any cloud folder and triage it.
/// - Supports two deletion/removal paths when committing trashed cloud items:
///   1. **Direct Album Removal (`albums.batchRemoveMediaItems`)** for writable albums.
///   2. **"To Delete - SwipeDeck" Staging Album + Deep-Link to Google Photos Trash** (since Google's Photos Library API
///      strictly forbids third-party apps from permanently trashing photos uploaded by the camera app).
@MainActor
@Observable
public final class GooglePhotosCloudService: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = GooglePhotosCloudService()

    public static let stagingAlbumTitle = "To Delete - SwipeDeck"

    private let clientIDKey = "swipedeck.google.client_id"
    private let accessTokenKey = "swipedeck.google.access_token"
    private let userEmailKey = "swipedeck.google.user_email"

    public var clientID: String {
        didSet {
            UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientIDKey)
        }
    }

    public private(set) var accessToken: String? {
        didSet {
            if let token = accessToken {
                UserDefaults.standard.set(token, forKey: accessTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: accessTokenKey)
            }
        }
    }

    public private(set) var connectedEmail: String? {
        didSet {
            UserDefaults.standard.set(connectedEmail, forKey: userEmailKey)
        }
    }

    public private(set) var albums: [GooglePhotosAlbum] = []
    public private(set) var isAuthenticating = false
    public private(set) var isLoadingAlbums = false
    public var statusMessage: String?

    /// Cache of `asset.id` ("gphoto_<id>") -> `baseUrl` for fast image/thumbnail loading in `AssetPrefetchPipeline`.
    private var remoteBaseURLByAssetID: [String: String] = [:]
    private var inMemoryImageCache = NSCache<NSString, UIImage>()

    public var isConnected: Bool {
        guard let token = accessToken, !token.isEmpty else { return false }
        return true
    }

    private override init() {
        self.clientID = UserDefaults.standard.string(forKey: clientIDKey) ?? ""
        self.accessToken = UserDefaults.standard.string(forKey: accessTokenKey)
        self.connectedEmail = UserDefaults.standard.string(forKey: userEmailKey)
        super.init()
    }

    // MARK: - OAuth 2.0 PKCE Sign-In (ASWebAuthenticationSession)

    public func signInWithGoogle() async throws {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else {
            throw NSError(
                domain: "GooglePhotosCloudService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Please enter your iOS Google OAuth Client ID first."]
            )
        }

        // Derive reversed client ID scheme required by Google iOS OAuth clients:
        // e.g. "12345-abcdef.apps.googleusercontent.com" -> "com.googleusercontent.apps.12345-abcdef"
        let callbackScheme = Self.reversedClientIDScheme(from: trimmedClientID)
        let redirectURI = "\(callbackScheme):/oauthredirect"
        let verifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: trimmedClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(
                name: "scope",
                value: "https://www.googleapis.com/auth/photoslibrary.readonly https://www.googleapis.com/auth/photoslibrary.appendonly https://www.googleapis.com/auth/photoslibrary.sharing email"
            ),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = comps.url else {
            throw NSError(domain: "GooglePhotosCloudService", code: 401, userInfo: nil)
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "GooglePhotosCloudService",
                            code: 402,
                            userInfo: [NSLocalizedDescriptionKey: "Sign-in was cancelled."]
                        )
                    )
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let urlComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = urlComps.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw NSError(
                domain: "GooglePhotosCloudService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "No authorization code returned from Google."]
            )
        }

        try await exchangeCodeForToken(
            code: code,
            clientID: trimmedClientID,
            redirectURI: redirectURI,
            codeVerifier: verifier
        )
        await fetchAlbums()
    }

    public func disconnectAccount() {
        accessToken = nil
        connectedEmail = nil
        albums.removeAll()
        remoteBaseURLByAssetID.removeAll()
        statusMessage = nil
    }

    // MARK: - Fetch Albums & Media Items

    public func fetchAlbums() async {
        guard let token = accessToken, !token.isEmpty else { return }
        isLoadingAlbums = true
        defer { isLoadingAlbums = false }

        do {
            var request = URLRequest(url: URL(string: "https://photoslibrary.googleapis.com/v1/albums?pageSize=50")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                statusMessage = "Could not load Google Photos albums. Check OAuth token."
                return
            }

            let decoded = try JSONDecoder().decode(AlbumsListResponse.self, from: data)
            self.albums = (decoded.albums ?? []).map { raw in
                let assetKey = "gphoto_cover_\(raw.id)"
                if let cover = raw.coverPhotoBaseUrl {
                    remoteBaseURLByAssetID[assetKey] = cover
                }
                return GooglePhotosAlbum(
                    id: raw.id,
                    title: raw.title ?? "Untitled Folder",
                    mediaItemsCount: Int(raw.mediaItemsCount ?? "0") ?? 0,
                    coverPhotoBaseUrl: raw.coverPhotoBaseUrl,
                    productUrl: raw.productUrl,
                    isWriteable: raw.isWriteable ?? false
                )
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Fetches media items inside a specific Google Photos folder/album (or the main stream if `albumID == nil`).
    public func fetchMediaAssets(albumID: String?, excludedAssetIDs: Set<String>) async -> [MediaAsset] {
        guard let token = accessToken, !token.isEmpty else { return [] }

        do {
            let items: [RawMediaItem]
            if let albumID {
                var request = URLRequest(url: URL(string: "https://photoslibrary.googleapis.com/v1/mediaItems:search")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = ["albumId": albumID, "pageSize": 100]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, _) = try await URLSession.shared.data(for: request)
                let decoded = try JSONDecoder().decode(MediaItemsListResponse.self, from: data)
                items = decoded.mediaItems ?? []
            } else {
                var request = URLRequest(url: URL(string: "https://photoslibrary.googleapis.com/v1/mediaItems?pageSize=100")!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, _) = try await URLSession.shared.data(for: request)
                let decoded = try JSONDecoder().decode(MediaItemsListResponse.self, from: data)
                items = decoded.mediaItems ?? []
            }

            let isoFormatter = ISO8601DateFormatter()
            var assets: [MediaAsset] = []

            for item in items {
                let syntheticID = "gphoto_\(item.id)"
                remoteBaseURLByAssetID[syntheticID] = item.baseUrl
                if excludedAssetIDs.contains(syntheticID) { continue }

                let width = Int(item.mediaMetadata?.width ?? "1080") ?? 1080
                let height = Int(item.mediaMetadata?.height ?? "1920") ?? 1920
                let creationDate = item.mediaMetadata?.creationTime.flatMap { isoFormatter.date(from: $0) }
                let isVideo = item.mimeType?.lowercased().contains("video") == true
                let estimatedBytes = isVideo ? Int64(12_500_000) : Int64(Double(width * height) * 0.24)

                assets.append(
                    MediaAsset(
                        id: syntheticID,
                        kind: isVideo ? .video : .photo,
                        creationDate: creationDate,
                        pixelWidth: width,
                        pixelHeight: height,
                        duration: 0,
                        isFavorite: false,
                        fileSizeBytes: estimatedBytes,
                        remoteBaseURL: item.baseUrl,
                        remoteProductURL: item.productUrl,
                        googleMediaItemID: item.id
                    )
                )
            }
            return assets
        } catch {
            statusMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - Deletion & Album Removal Execution

    /// Executes cleanup for left-swiped Google Photos cloud items:
    /// 1. First attempts to remove them directly from their source album (`batchRemoveMediaItems`) if writable,
    ///    and stages them into the `"To Delete - SwipeDeck"` album (`batchAddMediaItems`) so the user can empty them
    ///    into Google Photos Trash in two taps.
    /// 2. Returns the Google Photos album `productUrl` so the user can optionally jump straight to Google Photos to confirm permanent trash.
    public func commitCloudTrashItems(assetIDs: [String]) async throws -> URL? {
        guard let token = accessToken, !token.isEmpty else { return nil }
        let rawMediaIDs = assetIDs.map { $0.replacingOccurrences(of: "gphoto_", with: "") }.filter { !$0.isEmpty }
        guard !rawMediaIDs.isEmpty else { return nil }

        let targetAlbum = try await findOrCreateStagingAlbum(token: token)

        // Add items in chunks of 50 (Google Photos API limit per request)
        for chunkStart in stride(from: 0, to: rawMediaIDs.count, by: 50) {
            let chunk = Array(rawMediaIDs[chunkStart..<min(rawMediaIDs.count, chunkStart + 50)])
            var request = URLRequest(
                url: URL(string: "https://photoslibrary.googleapis.com/v1/albums/\(targetAlbum.id):batchAddMediaItems")!
            )
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["mediaItemIds": chunk]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: request)
        }

        if let urlStr = targetAlbum.productUrl, let url = URL(string: urlStr) {
            return url
        }
        return URL(string: "googlephotos://")
    }

    /// Loads a remote image for a `"gphoto_..."` asset ID with width/height parameters.
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

        guard let baseURL = remoteBaseURLByAssetID[assetID],
              let sizedURL = URL(string: "\(baseURL)=w\(pixelWidth)-h\(pixelHeight)") else {
            onResult(nil)
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: sizedURL)
                if let image = UIImage(data: data) {
                    self.inMemoryImageCache.setObject(image, forKey: cacheKey)
                    onResult(image)
                } else {
                    onResult(nil)
                }
            } catch {
                onResult(nil)
            }
        }
    }

    // MARK: - Internal Helpers

    private func findOrCreateStagingAlbum(token: String) async throws -> GooglePhotosAlbum {
        if let existing = albums.first(where: { $0.title == Self.stagingAlbumTitle }) {
            return existing
        }

        var request = URLRequest(url: URL(string: "https://photoslibrary.googleapis.com/v1/albums")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["album": ["title": Self.stagingAlbumTitle]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let raw = try JSONDecoder().decode(RawAlbum.self, from: data)
        let created = GooglePhotosAlbum(
            id: raw.id,
            title: raw.title ?? Self.stagingAlbumTitle,
            mediaItemsCount: 0,
            coverPhotoBaseUrl: raw.coverPhotoBaseUrl,
            productUrl: raw.productUrl,
            isWriteable: true
        )
        albums.insert(created, at: 0)
        return created
    }

    private func exchangeCodeForToken(
        code: String,
        clientID: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        let formString = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        request.httpBody = formString.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        self.accessToken = tokenResponse.access_token
        self.connectedEmail = "Google Photos Connected"
    }

    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
                return keyWindow
            }
            return ASPresentationAnchor()
        }
    }

    private static func reversedClientIDScheme(from clientID: String) -> String {
        let parts = clientID.split(separator: ".").reversed()
        return parts.joined(separator: ".")
    }

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Codable DTOs

    private struct OAuthTokenResponse: Decodable {
        let access_token: String
    }

    private struct AlbumsListResponse: Decodable {
        let albums: [RawAlbum]?
    }

    private struct RawAlbum: Decodable {
        let id: String
        let title: String?
        let productUrl: String?
        let isWriteable: Bool?
        let mediaItemsCount: String?
        let coverPhotoBaseUrl: String?
    }

    private struct MediaItemsListResponse: Decodable {
        let mediaItems: [RawMediaItem]?
    }

    private struct RawMediaItem: Decodable {
        let id: String
        let productUrl: String?
        let baseUrl: String
        let mimeType: String?
        let mediaMetadata: RawMediaMetadata?
    }

    private struct RawMediaMetadata: Decodable {
        let creationTime: String?
        let width: String?
        let height: String?
    }
}
