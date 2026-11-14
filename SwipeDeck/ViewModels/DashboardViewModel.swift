import Foundation
import SwiftUI

/// Drives the Home Dashboard (`HomeDashboardView`):
/// - Loads Source Decks, Month/Year Buckets, User Albums, and Smart Storage Sieves (Heavy Hitters).
/// - Displays Lifetime Storage Reclaimed statistics and the "Include previously kept photos" toggle.
@MainActor
@Observable
public final class DashboardViewModel {
    public private(set) var sourceDecks: [DeckSummaryItem] = []
    public private(set) var monthDecks: [DeckSummaryItem] = []
    public private(set) var userAlbumDecks: [DeckSummaryItem] = []
    public private(set) var lifetimeStats = LifetimeStatsSnapshot()
    public private(set) var isLoading = false

    /// Toggle allowing the user to re-triage photos previously marked as "Keep" (PRD Section 4.3).
    public var includePreviouslyKept: Bool = false {
        didSet {
            if oldValue != includePreviouslyKept {
                Task { await refreshDashboard() }
            }
        }
    }

    /// Controls presentation of the custom date range picker sheet.
    public var isPresentingCustomDateRangeSheet = false

    private let ledger: LedgerActor
    private let queryService = PhotoDeckQueryService.shared

    public init(ledger: LedgerActor) {
        self.ledger = ledger
    }

    public func refreshDashboard() async {
        isLoading = true
        let reviewed = (try? await ledger.fetchReviewedIdentifiers()) ?? (kept: [], stagedTrash: [])
        var excludedIDs = reviewed.stagedTrash
        if !includePreviouslyKept {
            excludedIDs.formUnion(reviewed.kept)
        }

        async let summariesTask = queryService.fetchDashboardSummaries(excludedAssetIDs: excludedIDs)
        async let statsTask = ledger.fetchLifetimeStats()

        let summaries = await summariesTask
        let stats = (try? await statsTask) ?? LifetimeStatsSnapshot()

        self.sourceDecks = summaries.sources
        self.monthDecks = summaries.months
        self.userAlbumDecks = summaries.userAlbums
        self.lifetimeStats = stats
        self.isLoading = false
    }
}
