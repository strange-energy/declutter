import Foundation

/// Defines all Deck Generators available on the Home Dashboard (PRD Section 4.1).
public enum DeckFilter: Hashable, Codable, Identifiable, Sendable {
    // MARK: - By Source
    case allPhotos
    case favorites
    case screenshots
    case screenRecordings
    case messagingApps // WhatsApp / Telegram Saved Media
    case userAlbum(id: String, title: String)

    // MARK: - By Timeframe
    case onThisDay
    case monthYear(year: Int, month: Int)
    case customDateRange(start: Date, end: Date)

    // MARK: - Smart Storage Sieves
    case heavyHitters // Videos and photos sorted by file size (largest first)

    // MARK: - Google Photos Cloud Companion (Milestone 3B)
    case googlePhotosAll
    case googlePhotosAlbum(albumID: String, title: String)

    public var isGooglePhotosDeck: Bool {
        switch self {
        case .googlePhotosAll, .googlePhotosAlbum:
            return true
        default:
            return false
        }
    }

    public var id: String {
        switch self {
        case .allPhotos:
            return "source_all_photos"
        case .favorites:
            return "source_favorites"
        case .screenshots:
            return "source_screenshots"
        case .screenRecordings:
            return "source_screen_recordings"
        case .messagingApps:
            return "source_messaging_apps"
        case .userAlbum(let id, _):
            return "album_\(id)"
        case .onThisDay:
            return "timeframe_on_this_day"
        case .monthYear(let year, let month):
            return String(format: "timeframe_month_%04d_%02d", year, month)
        case .customDateRange(let start, let end):
            return "timeframe_range_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))"
        case .heavyHitters:
            return "sieve_heavy_hitters"
        case .googlePhotosAll:
            return "gphoto_all_cloud"
        case .googlePhotosAlbum(let albumID, _):
            return "gphoto_album_\(albumID)"
        }
    }

    public var title: String {
        switch self {
        case .allPhotos:
            return "All Photos"
        case .favorites:
            return "Favorites"
        case .screenshots:
            return "Screenshots"
        case .screenRecordings:
            return "Screen Recordings"
        case .messagingApps:
            return "WhatsApp & Telegram"
        case .userAlbum(_, let title):
            return title
        case .onThisDay:
            return "On This Day"
        case .monthYear(let year, let month):
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            if let date = Calendar.current.date(from: components) {
                return date.formatted(.dateTime.month(.wide).year())
            }
            return "\(month)/\(year)"
        case .customDateRange(let start, let end):
            let startStr = start.formatted(.dateTime.month(.abbreviated).day().year())
            let endStr = end.formatted(.dateTime.month(.abbreviated).day().year())
            return "\(startStr) – \(endStr)"
        case .heavyHitters:
            return "Heavy Hitters"
        case .googlePhotosAll:
            return "Google Photos Stream"
        case .googlePhotosAlbum(_, let title):
            return title
        }
    }

    public var subtitle: String {
        switch self {
        case .allPhotos:
            return "Chronological camera roll triage"
        case .favorites:
            return "Curate your starred shots"
        case .screenshots:
            return "Clear out temporary captures"
        case .screenRecordings:
            return "High-bitrate screen captures"
        case .messagingApps:
            return "Saved media from chat apps"
        case .userAlbum:
            return "Custom album collection"
        case .onThisDay:
            return "Memories from today across all years"
        case .monthYear:
            return "Monthly archive cleanup"
        case .customDateRange:
            return "Targeted date window"
        case .heavyHitters:
            return "Largest videos & photos first"
        case .googlePhotosAll:
            return "Cloud library triage"
        case .googlePhotosAlbum:
            return "Google Photos cloud folder"
        }
    }

    public var systemIcon: String {
        switch self {
        case .allPhotos:
            return "photo.on.rectangle.angled"
        case .favorites:
            return "heart.fill"
        case .screenshots:
            return "camera.viewfinder"
        case .screenRecordings:
            return "record.circle"
        case .messagingApps:
            return "bubble.left.and.bubble.right.fill"
        case .userAlbum:
            return "rectangle.stack.fill"
        case .onThisDay:
            return "calendar.badge.clock"
        case .monthYear:
            return "calendar"
        case .customDateRange:
            return "calendar.day.timeline.left"
        case .heavyHitters:
            return "externaldrive.fill.badge.timemachine"
        case .googlePhotosAll, .googlePhotosAlbum:
            return "cloud.fill"
        }
    }
}
