import Foundation
import SwiftUI

/// Coordinates an active single-card triage session for a selected `DeckFilter`:
/// - Manages the active deck queue, current card cursor, and reversible undo history stack.
/// - Updates `AssetPrefetchPipeline` on every swipe for zero-latency 120Hz transitions.
/// - Writes session checkpoints and dispositions asynchronously via `LedgerActor`.
@MainActor
@Observable
public final class DeckSessionViewModel {
    public let filter: DeckFilter
    public private(set) var deck: [MediaAsset] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var undoStack: [SwipeHistoryEntry] = []
    public private(set) var isLoading: Bool = true

    /// Toggled by single-tap on the active card (PRD Section 3.1).
    public var isMetadataOverlayVisible: Bool = false
    /// Cached metadata for the currently visible top card.
    public private(set) var activeCardMetadata: AssetMetadata?
    /// Session-wide mute/unmute state for Live Photos & Videos (PRD Section 7).
    public var isAudioMuted: Bool = true
    /// User preference toggle to include previously kept photos when opening a folder/month (PRD Section 4.3).
    public var includePreviouslyKept: Bool

    private let ledger: LedgerActor
    private let trashVM: TrashStagingViewModel
    private let queryService = PhotoDeckQueryService.shared
    private let prefetchPipeline = AssetPrefetchPipeline.shared

    public init(
        filter: DeckFilter,
        includePreviouslyKept: Bool = false,
        ledger: LedgerActor,
        trashVM: TrashStagingViewModel
    ) {
        self.filter = filter
        self.includePreviouslyKept = includePreviouslyKept
        self.ledger = ledger
        self.trashVM = trashVM
    }

    // MARK: - Computed Stack Helpers

    public var isDeckFinished: Bool {
        !isLoading && currentIndex >= deck.count
    }

    public var totalCount: Int {
        deck.count
    }

    /// Progress counter (1-based for display, e.g., `142 / 300`).
    public var progressDisplayIndex: Int {
        guard !deck.isEmpty else { return 0 }
        return min(currentIndex + 1, deck.count)
    }

    public var progressFraction: Double {
        guard !deck.isEmpty else { return 0.0 }
        return Double(min(currentIndex, deck.count)) / Double(deck.count)
    }

    /// Returns up to 3 visible cards for the Center Canvas 3D depth stack (`scale: 1.0`, `0.95`, `0.90`).
    public var visibleStackCards: [(stackDepth: Int, asset: MediaAsset)] {
        guard currentIndex < deck.count else { return [] }
        let end = min(deck.count - 1, currentIndex + 2)
        return (currentIndex...end).map { idx in
            (stackDepth: idx - currentIndex, asset: deck[idx])
        }
    }

    public var currentTopAsset: MediaAsset? {
        guard currentIndex >= 0, currentIndex < deck.count else { return nil }
        return deck[currentIndex]
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    // MARK: - Load & Checkpoint Recovery

    public func loadSession() async {
        isLoading = true
        HapticEngine.shared.prepareAll()

        let reviewed = (try? await ledger.fetchReviewedIdentifiers()) ?? (kept: [], stagedTrash: [])
        var excludedIDs = reviewed.stagedTrash
        if !includePreviouslyKept {
            excludedIDs.formUnion(reviewed.kept)
        }

        let fetchedAssets = await queryService.buildDeck(for: filter, excludedAssetIDs: excludedIDs)

        // Restore saved session checkpoint order if available and valid
        if let checkpoint = try? await ledger.loadDeckCheckpoint(deckKey: filter.id),
           !checkpoint.orderedIDs.isEmpty {
            let assetByID = Dictionary(uniqueKeysWithValues: fetchedAssets.map { ($0.id, $0) })
            var restored: [MediaAsset] = []
            var seen = Set<String>()
            for id in checkpoint.orderedIDs {
                if let match = assetByID[id] {
                    restored.append(match)
                    seen.insert(id)
                }
            }
            for asset in fetchedAssets where !seen.contains(asset.id) {
                restored.append(asset)
            }
            self.deck = restored
            self.currentIndex = min(max(0, checkpoint.currentIndex), max(0, restored.count - 1))
        } else {
            self.deck = fetchedAssets
            self.currentIndex = 0
        }

        isLoading = false
        prefetchPipeline.updatePrefetchWindow(deck: deck, currentIndex: currentIndex)
        refreshTopCardMetadataIfNeeded()
    }

    // MARK: - 4-Way Gesture Execution (PRD Section 3.1)

    public func performAction(_ action: SwipeAction) {
        switch action {
        case .keep:
            commitKeep()
        case .trash:
            commitTrash()
        case .deferToBack:
            commitDeferToBack()
        case .undo:
            commitUndo()
        }
    }

    /// Swipe Right (Keep): Marks asset as "Reviewed & Kept" so it never appears in future triage sessions.
    private func commitKeep() {
        guard let asset = currentTopAsset else { return }
        HapticEngine.shared.fireKeepCommit()

        let previousIdx = currentIndex
        undoStack.append(SwipeHistoryEntry(asset: asset, action: .keep, previousIndex: previousIdx))
        currentIndex += 1

        prefetchPipeline.updatePrefetchWindow(deck: deck, currentIndex: currentIndex)
        refreshTopCardMetadataIfNeeded()

        let deckID = filter.id
        let orderedIDs = deck.map(\.id)
        let newIdx = currentIndex

        Task {
            let bytes = asset.fileSizeBytes > 0
                ? asset.fileSizeBytes
                : await AssetMetadataExtractor.shared.fileSizeBytes(for: asset.id)
            try? await ledger.recordDisposition(
                assetID: asset.id,
                disposition: .kept,
                fileSizeBytes: bytes,
                mediaKind: asset.kind,
                sourceDeckID: deckID
            )
            try? await ledger.saveDeckCheckpoint(
                deckKey: deckID,
                orderedAssetIDs: orderedIDs,
                currentIndex: newIdx
            )
        }
    }

    /// Swipe Left (Stage for Deletion): Places asset into the in-app Staging Trash Queue.
    private func commitTrash() {
        guard let asset = currentTopAsset else { return }
        HapticEngine.shared.fireTrashCommit()

        let previousIdx = currentIndex
        undoStack.append(SwipeHistoryEntry(asset: asset, action: .trash, previousIndex: previousIdx))
        currentIndex += 1

        trashVM.stageForTrash(asset: asset, sourceDeckID: filter.id)
        prefetchPipeline.updatePrefetchWindow(deck: deck, currentIndex: currentIndex)
        refreshTopCardMetadataIfNeeded()

        let deckID = filter.id
        let orderedIDs = deck.map(\.id)
        let newIdx = currentIndex

        Task {
            try? await ledger.saveDeckCheckpoint(
                deckKey: deckID,
                orderedAssetIDs: orderedIDs,
                currentIndex: newIdx
            )
        }

        // If user just finished the deck and has staged trash items, automatically surface the Review & Commit sheet
        if isDeckFinished && trashVM.stagedCount > 0 {
            trashVM.isPresentingCommitSheet = true
        }
    }

    /// Swipe Up (Push to Back of Stack): Moves the current asset to the end of the active session's queue.
    private func commitDeferToBack() {
        guard currentIndex < deck.count else { return }
        HapticEngine.shared.fireUtilityCommit()

        let asset = deck.remove(at: currentIndex)
        deck.append(asset)
        undoStack.append(SwipeHistoryEntry(asset: asset, action: .deferToBack, previousIndex: currentIndex))

        prefetchPipeline.updatePrefetchWindow(deck: deck, currentIndex: currentIndex)
        refreshTopCardMetadataIfNeeded()

        let deckID = filter.id
        let orderedIDs = deck.map(\.id)
        let newIdx = currentIndex

        Task {
            try? await ledger.saveDeckCheckpoint(
                deckKey: deckID,
                orderedAssetIDs: orderedIDs,
                currentIndex: newIdx
            )
        }
    }

    /// Swipe Down (Undo Last Action): Recalls the previously swiped card back to the top of the deck.
    public func commitUndo() {
        guard let lastEntry = undoStack.popLast() else { return }
        HapticEngine.shared.fireUtilityCommit()

        switch lastEntry.action {
        case .keep:
            currentIndex = max(0, lastEntry.previousIndex)
            Task {
                try? await ledger.removeDisposition(assetID: lastEntry.asset.id)
            }

        case .trash:
            currentIndex = max(0, lastEntry.previousIndex)
            trashVM.unstageFromTrash(assetID: lastEntry.asset.id)

        case .deferToBack:
            // Remove from back of deck and re-insert at currentIndex
            if let lastDeckIdx = deck.lastIndex(where: { $0.id == lastEntry.asset.id }) {
                let removed = deck.remove(at: lastDeckIdx)
                let targetIdx = min(lastEntry.previousIndex, deck.count)
                deck.insert(removed, at: targetIdx)
                currentIndex = targetIdx
            }

        case .undo:
            break
        }

        prefetchPipeline.updatePrefetchWindow(deck: deck, currentIndex: currentIndex)
        refreshTopCardMetadataIfNeeded()

        let deckID = filter.id
        let orderedIDs = deck.map(\.id)
        let newIdx = currentIndex
        Task {
            try? await ledger.saveDeckCheckpoint(
                deckKey: deckID,
                orderedAssetIDs: orderedIDs,
                currentIndex: newIdx
            )
        }
    }

    // MARK: - Metadata Overlay

    public func toggleMetadataOverlay() {
        HapticEngine.shared.fireSelectionTick()
        isMetadataOverlayVisible.toggle()
        refreshTopCardMetadataIfNeeded()
    }

    private func refreshTopCardMetadataIfNeeded() {
        guard isMetadataOverlayVisible, let topAsset = currentTopAsset else {
            activeCardMetadata = nil
            return
        }
        Task {
            let meta = await AssetMetadataExtractor.shared.extractMetadata(for: topAsset)
            if self.currentTopAsset?.id == topAsset.id {
                self.activeCardMetadata = meta
            }
        }
    }

    public func cleanupOnDisappear() {
        prefetchPipeline.stopCachingAll()
    }
}
