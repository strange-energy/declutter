import SwiftUI

/// Typography system using SF Pro Rounded for headers/counters and SF Mono for technical EXIF metadata (PRD Section 6.1).
public enum SwipeDeckTypography {
    public static func roundedTitle(_ size: CGFloat = 28, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    public static func roundedHeadline(_ size: CGFloat = 18, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    public static func roundedCounter(_ size: CGFloat = 15, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    public static func monoMetadata(_ size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    public static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

public extension View {
    func roundedStatStyle(size: CGFloat = 15, color: Color = SwipeDeckTheme.textPrimary) -> some View {
        self
            .font(SwipeDeckTypography.roundedCounter(size))
            .monospacedDigit()
            .foregroundStyle(color)
    }

    func exifMonoStyle(size: CGFloat = 12, color: Color = SwipeDeckTheme.textPrimary) -> some View {
        self
            .font(SwipeDeckTypography.monoMetadata(size))
            .foregroundStyle(color)
    }
}
