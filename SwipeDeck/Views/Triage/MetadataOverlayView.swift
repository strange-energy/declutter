import SwiftUI

/// Single-tap technical metadata overlay using `SF Mono` (PRD Section 3.1 & 6.1):
/// Displays Date, Location, File Size, Resolution, Camera/Lens info, Exposure (ISO/Shutter/Aperture), and iCloud status.
public struct MetadataOverlayView: View {
    public let asset: MediaAsset
    public let metadata: AssetMetadata?

    public init(asset: MediaAsset, metadata: AssetMetadata?) {
        self.asset = asset
        self.metadata = metadata
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(metadata?.filename ?? "ASSET")
                    .exifMonoStyle(size: 13, color: SwipeDeckTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(formattedByteSize)
                    .exifMonoStyle(size: 12, color: SwipeDeckTheme.accentKeep)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SwipeDeckTheme.accentKeep.opacity(0.16), in: Capsule())
            }

            Divider()
                .overlay(SwipeDeckTheme.borderSubtle)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                if let date = metadata?.creationDate ?? asset.creationDate {
                    metadataRow(
                        icon: "calendar",
                        label: "DATE",
                        value: date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
                    )
                }

                metadataRow(
                    icon: "aspectratio",
                    label: "RES",
                    value: metadata?.dimensions ?? "\(asset.resolutionText) (\(asset.megapixelsText))"
                )

                if let cameraLine = metadata?.cameraSummaryLine {
                    metadataRow(icon: "camera.aperture", label: "LENS", value: cameraLine)
                }

                if let exposureLine = metadata?.exposureSummaryLine {
                    metadataRow(icon: "dial.low", label: "EXIF", value: exposureLine)
                }

                if let location = metadata?.locationName {
                    metadataRow(icon: "location.fill", label: "GPS", value: location)
                }

                if metadata?.isStoredIniCloud == true {
                    metadataRow(icon: "icloud.fill", label: "CLOUD", value: "iCloud Optimized")
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
        )
        .padding(16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var formattedByteSize: String {
        if let meta = metadata, meta.fileSizeBytes > 0 {
            return meta.formattedFileSize
        }
        if asset.fileSizeBytes > 0 {
            return ByteCountFormatter.string(fromByteCount: asset.fileSizeBytes, countStyle: .file)
        }
        return "Calculating…"
    }

    @ViewBuilder
    private func metadataRow(icon: String, label: String, value: String) -> some View {
        GridRow {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SwipeDeckTheme.textSecondary)
                    .frame(width: 14)
                Text(label)
                    .exifMonoStyle(size: 11, color: SwipeDeckTheme.textSecondary)
            }
            Text(value)
                .exifMonoStyle(size: 12, color: SwipeDeckTheme.textPrimary)
                .lineLimit(1)
        }
    }
}
