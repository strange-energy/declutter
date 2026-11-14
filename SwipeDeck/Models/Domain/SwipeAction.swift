import Foundation

/// Four-directional triage gesture actions (PRD Section 3.1).
public enum SwipeAction: String, Codable, Sendable {
    /// Swipe Right: Marks the asset as "Reviewed & Kept" so it never appears in future triage sessions.
    case keep
    /// Swipe Left: Places the asset into the Staging Trash Queue.
    case trash
    /// Swipe Up: Pushes the current asset to the back of the active session's queue for later decision-making.
    case deferToBack
    /// Swipe Down: Recalls the previously swiped card back to the top of the deck.
    case undo
}

/// Represents a reversible entry on the in-memory undo stack so Swipe Down restores exact deck state.
public struct SwipeHistoryEntry: Sendable {
    public let asset: MediaAsset
    public let action: SwipeAction
    public let previousIndex: Int

    public init(asset: MediaAsset, action: SwipeAction, previousIndex: Int) {
        self.asset = asset
        self.action = action
        self.previousIndex = previousIndex
    }
}
