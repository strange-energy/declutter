import SwiftUI

/// Pure OLED Dark Mode and semantic accents as specified in PRD Section 6.1.
public enum SwipeDeckTheme {
    // MARK: - Surfaces
    /// Pure OLED black (#000000) to prevent color-cast illusions on photography.
    public static let backgroundPrimary = Color(red: 0.0, green: 0.0, blue: 0.0)
    /// Elevated dark card surface (#1C1C1E).
    public static let surfaceElevated = Color(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0)
    /// Secondary elevated surface (#2C2C2E).
    public static let surfaceSecondary = Color(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 46.0 / 255.0)
    /// Subtle hairline border (#38383A).
    public static let borderSubtle = Color(red: 56.0 / 255.0, green: 56.0 / 255.0, blue: 58.0 / 255.0)

    // MARK: - Semantic Gesture Accents
    /// Swipe Right (Keep) — Emerald Green (#30D158)
    public static let accentKeep = Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0)
    /// Swipe Left (Delete / Stage Trash) — Coral Red (#FF453A)
    public static let accentDelete = Color(red: 255.0 / 255.0, green: 69.0 / 255.0, blue: 58.0 / 255.0)
    /// Swipe Up (Defer / Back of Stack) — Electric Blue (#0A84FF)
    public static let accentDefer = Color(red: 10.0 / 255.0, green: 132.0 / 255.0, blue: 255.0 / 255.0)
    /// Swipe Down (Undo) — Amber (#FFD60A)
    public static let accentUndo = Color(red: 255.0 / 255.0, green: 214.0 / 255.0, blue: 10.0 / 255.0)

    // MARK: - Text Colors
    public static let textPrimary = Color.white
    public static let textSecondary = Color(white: 0.68)
    public static let textTertiary = Color(white: 0.45)

    // MARK: - Layout & Physics Constants
    /// Horizontal drag distance (in points) required to commit Keep or Trash.
    public static let horizontalSwipeThreshold: CGFloat = 120.0
    /// Vertical drag distance (in points) required to commit Defer (Up) or Undo (Down).
    public static let verticalSwipeThreshold: CGFloat = 100.0
    /// Critically damped spring response (PRD Section 6.3).
    public static let springResponse: Double = 0.32
    /// Critically damped spring damping fraction (PRD Section 6.3).
    public static let springDamping: Double = 0.78
    /// Card corner radius.
    public static let cardCornerRadius: CGFloat = 24.0
}
