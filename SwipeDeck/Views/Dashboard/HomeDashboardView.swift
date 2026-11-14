import SwiftUI

/// Home Dashboard providing Deck Generators (By Source, By Timeframe, Smart Storage Sieves)
/// and Lifetime Decluttering telemetry (PRD Section 4.1, 4.3, 6.1).
public struct HomeDashboardView: View {
    @Bindable public var dashboardVM: DashboardViewModel
    @Bindable public var trashVM: TrashStagingViewModel
    public let ledger: LedgerActor

    @State private var selectedDeckFilter: DeckFilter?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    public init(
        dashboardVM: DashboardViewModel,
        trashVM: TrashStagingViewModel,
        ledger: LedgerActor
    ) {
        self.dashboardVM = dashboardVM
        self.trashVM = trashVM
        self.ledger = ledger
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                SwipeDeckTheme.backgroundPrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        // 1. Top Header & Trash Pill
                        topDashboardHeader

                        // 2. Lifetime Storage Freed Banner
                        lifetimeTelemetryBanner

                        // 3. Smart Storage Sieve ("Heavy Hitters")
                        if let heavyHitters = dashboardVM.sourceDecks.first(where: { $0.filter == .heavyHitters }) {
                            heavyHittersHeroCard(summary: heavyHitters)
                        }

                        // 4. Deck Generators: By Source
                        sectionHeader(title: "BY SOURCE", subtitle: "Targeted media categories")
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(dashboardVM.sourceDecks.filter { $0.filter != .heavyHitters }) { summary in
                                DeckSummaryCardView(summary: summary) {
                                    selectedDeckFilter = summary.filter
                                }
                            }
                        }

                        // 5. Deck Generators: By Timeframe (Month/Year & Custom Range)
                        HStack {
                            sectionHeader(title: "BY TIMEFRAME", subtitle: "Monthly camera roll cleanup")
                            Spacer()
                            Button {
                                dashboardVM.isPresentingCustomDateRangeSheet = true
                            } label: {
                                Label("Custom Range", systemImage: "calendar.badge.plus")
                                    .font(SwipeDeckTypography.roundedCounter(13))
                                    .foregroundStyle(SwipeDeckTheme.accentDefer)
                            }
                            .buttonStyle(.plain)
                        }

                        if dashboardVM.monthDecks.isEmpty {
                            Text("No monthly photo buckets found.")
                                .font(SwipeDeckTypography.body(14))
                                .foregroundStyle(SwipeDeckTheme.textTertiary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(dashboardVM.monthDecks) { monthSummary in
                                        MonthBucketCardView(summary: monthSummary) {
                                            selectedDeckFilter = monthSummary.filter
                                        }
                                    }
                                }
                            }
                        }

                        // 6. User Albums (if any exist)
                        if !dashboardVM.userAlbumDecks.isEmpty {
                            sectionHeader(title: "USER ALBUMS", subtitle: "Your personal collections")
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(dashboardVM.userAlbumDecks) { albumSummary in
                                    DeckSummaryCardView(summary: albumSummary) {
                                        selectedDeckFilter = albumSummary.filter
                                    }
                                }
                            }
                        }

                        // 7. Reviewed Ledger Filter Toggle (PRD Section 4.3)
                        reviewedLedgerToggleCard
                    }
                    .padding(16)
                }
            }
            .navigationDestination(item: $selectedDeckFilter) { filter in
                SwipeDeckView(
                    sessionVM: DeckSessionViewModel(
                        filter: filter,
                        includePreviouslyKept: dashboardVM.includePreviouslyKept,
                        ledger: ledger,
                        trashVM: trashVM
                    ),
                    trashVM: trashVM,
                    onSessionEnded: {
                        Task {
                            await dashboardVM.refreshDashboard()
                        }
                    }
                )
            }
            .sheet(isPresented: $dashboardVM.isPresentingCustomDateRangeSheet) {
                CustomDateRangeSheet { customFilter in
                    selectedDeckFilter = customFilter
                }
            }
            .sheet(isPresented: $trashVM.isPresentingCommitSheet) {
                BatchCommitSheetView(trashVM: trashVM) {
                    Task {
                        await dashboardVM.refreshDashboard()
                    }
                }
            }
            .fullScreenCover(item: $trashVM.latestCommitReceipt) { receipt in
                StorageCelebrationView(receipt: receipt) {
                    trashVM.latestCommitReceipt = nil
                }
            }
            .task {
                await trashVM.reloadFromLedger()
                await dashboardVM.refreshDashboard()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var topDashboardHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SwipeDeck")
                    .font(SwipeDeckTypography.roundedTitle(30, weight: .heavy))
                    .foregroundStyle(SwipeDeckTheme.textPrimary)
                Text("Single-Card Photo Triage")
                    .font(SwipeDeckTypography.body(14))
                    .foregroundStyle(SwipeDeckTheme.textSecondary)
            }

            Spacer()

            TrashPillButton(
                count: trashVM.stagedCount,
                formattedBytes: trashVM.formattedTotalStagedSize
            ) {
                trashVM.isPresentingCommitSheet = true
            }
        }
    }

    private var lifetimeTelemetryBanner: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(SwipeDeckTheme.accentKeep.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SwipeDeckTheme.accentKeep)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("LIFETIME STORAGE RECLAIMED")
                    .exifMonoStyle(size: 10, color: SwipeDeckTheme.textSecondary)
                Text(dashboardVM.lifetimeStats.formattedBytesReclaimed)
                    .font(SwipeDeckTypography.roundedTitle(22, weight: .bold))
                    .foregroundStyle(SwipeDeckTheme.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(dashboardVM.lifetimeStats.totalItemsDeleted) deleted")
                    .exifMonoStyle(size: 11, color: SwipeDeckTheme.accentDelete)
                Text("\(dashboardVM.lifetimeStats.totalAssetsKept) kept")
                    .exifMonoStyle(size: 11, color: SwipeDeckTheme.accentKeep)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(SwipeDeckTheme.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func heavyHittersHeroCard(summary: DeckSummaryItem) -> some View {
        Button {
            selectedDeckFilter = .heavyHitters
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(SwipeDeckTheme.accentUndo)
                        Text("SMART STORAGE SIEVE")
                            .exifMonoStyle(size: 11, color: SwipeDeckTheme.accentUndo)
                    }

                    Text("Heavy Hitters")
                        .font(SwipeDeckTypography.roundedTitle(22, weight: .bold))
                        .foregroundStyle(SwipeDeckTheme.textPrimary)

                    Text("Videos & large photos sorted by file size (largest first) for rapid storage recovery.")
                        .font(SwipeDeckTypography.body(13))
                        .foregroundStyle(SwipeDeckTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(spacing: 4) {
                    Text("\(summary.unreviewedCount)")
                        .roundedStatStyle(size: 20, color: SwipeDeckTheme.accentUndo)
                    Text("to review")
                        .exifMonoStyle(size: 10, color: SwipeDeckTheme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(SwipeDeckTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SwipeDeckTheme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(SwipeDeckTheme.accentUndo.opacity(0.45), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var reviewedLedgerToggleCard: some View {
        Toggle(isOn: $dashboardVM.includePreviouslyKept) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Include Previously Kept Photos")
                    .font(SwipeDeckTypography.roundedHeadline(15, weight: .semibold))
                    .foregroundStyle(SwipeDeckTheme.textPrimary)
                Text("By default, Kept assets are hidden from future triage decks.")
                    .font(SwipeDeckTypography.body(12))
                    .foregroundStyle(SwipeDeckTheme.textSecondary)
            }
        }
        .tint(SwipeDeckTheme.accentKeep)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SwipeDeckTheme.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .exifMonoStyle(size: 11, color: SwipeDeckTheme.textSecondary)
            Text(subtitle)
                .font(SwipeDeckTypography.body(13))
                .foregroundStyle(SwipeDeckTheme.textTertiary)
        }
    }
}

// MARK: - Supporting Deck Cards

private struct DeckSummaryCardView: View {
    let summary: DeckSummaryItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: summary.filter.systemIcon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(SwipeDeckTheme.accentKeep)
                        .frame(width: 36, height: 36)
                        .background(SwipeDeckTheme.accentKeep.opacity(0.14), in: Circle())

                    Spacer()

                    Text("\(summary.unreviewedCount)")
                        .roundedStatStyle(size: 16, color: SwipeDeckTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SwipeDeckTheme.surfaceSecondary, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.filter.title)
                        .font(SwipeDeckTypography.roundedHeadline(16, weight: .bold))
                        .foregroundStyle(SwipeDeckTheme.textPrimary)
                        .lineLimit(1)

                    Text(summary.filter.subtitle)
                        .font(SwipeDeckTypography.body(12))
                        .foregroundStyle(SwipeDeckTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SwipeDeckTheme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MonthBucketCardView: View {
    let summary: DeckSummaryItem
    let onTap: () -> Void

    @State private var coverImage: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SwipeDeckTheme.surfaceElevated)
                    .frame(width: 156, height: 190)

                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 156, height: 190)
                        .clipped()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.filter.title)
                        .font(SwipeDeckTypography.roundedHeadline(15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(summary.unreviewedCount) left")
                        .exifMonoStyle(size: 11, color: SwipeDeckTheme.accentKeep)
                }
                .padding(12)
            }
            .frame(width: 156, height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .task(id: summary.coverAssetID) {
            guard let coverID = summary.coverAssetID else { return }
            AssetPrefetchPipeline.shared.requestThumbnail(
                for: coverID,
                pointSize: CGSize(width: 156, height: 190)
            ) { image in
                self.coverImage = image
            }
        }
    }
}
