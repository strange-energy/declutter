import Foundation
import SwiftData

/// Persists active deck ordering (including deferred/skipped items pushed to the back of the stack)
/// and current cursor position so force-closing the app never loses progress (PRD Section 4.3).
@Model
public final class DeckSessionCheckpoint {
    @Attribute(.unique)
    public var deckKey: String
    public var orderedAssetIDs: [String]
    public var currentIndex: Int
    public var lastUpdated: Date

    public init(
        deckKey: String,
        orderedAssetIDs: [String],
        currentIndex: Int,
        lastUpdated: Date = .now
    ) {
        self.deckKey = deckKey
        self.orderedAssetIDs = orderedAssetIDs
        self.currentIndex = currentIndex
        self.lastUpdated = lastUpdated
    }
}
