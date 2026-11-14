import Foundation
import CoreLocation

/// Rich technical metadata displayed when the user single-taps a card (PRD Section 3.1 & 6.1).
public struct AssetMetadata: Equatable, Sendable {
    public let assetID: String
    public let filename: String
    public let fileSizeBytes: Int64
    public let creationDate: Date?
    public let dimensions: String
    public let cameraModel: String?
    public let lensModel: String?
    public let iso: Int?
    public let shutterSpeed: String?
    public let aperture: String?
    public let focalLength: String?
    public let locationName: String?
    public let isStoredIniCloud: Bool

    public init(
        assetID: String,
        filename: String = "IMG_0000.HEIC",
        fileSizeBytes: Int64 = 0,
        creationDate: Date? = nil,
        dimensions: String = "—",
        cameraModel: String? = nil,
        lensModel: String? = nil,
        iso: Int? = nil,
        shutterSpeed: String? = nil,
        aperture: String? = nil,
        focalLength: String? = nil,
        locationName: String? = nil,
        isStoredIniCloud: Bool = false
    ) {
        self.assetID = assetID
        self.filename = filename
        self.fileSizeBytes = fileSizeBytes
        self.creationDate = creationDate
        self.dimensions = dimensions
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.iso = iso
        self.shutterSpeed = shutterSpeed
        self.aperture = aperture
        self.focalLength = focalLength
        self.locationName = locationName
        self.isStoredIniCloud = isStoredIniCloud
    }

    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    public var cameraSummaryLine: String? {
        let parts = [cameraModel, lensModel].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    public var exposureSummaryLine: String? {
        var tokens: [String] = []
        if let focalLength { tokens.append(focalLength) }
        if let aperture { tokens.append("ƒ/\(aperture)") }
        if let shutterSpeed { tokens.append("\(shutterSpeed)s") }
        if let iso { tokens.append("ISO \(iso)") }
        return tokens.isEmpty ? nil : tokens.joined(separator: "  ")
    }
}
