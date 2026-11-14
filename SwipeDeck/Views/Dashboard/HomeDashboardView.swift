import SwiftUI

/// Clean, low-friction Home Screen designed around a single primary CTA and a tabbed selector
/// ("Months", "Quick Clean", "Albums") so the user never faces decision fatigue before swiping.
public struct HomeDashboardView: View {
    public enum DeckTab: String, CaseIterable, Identifiable {
        case months = "By Month"
        case quickClean = "Categories"
        case albums = "Albums"

        public var id: String { rawValue }
    }

    @Bindable public var dashboardVM: DashboardViewModel
    @Bindable public var trashVM: TrashStagingViewModel
    public let ledger: LedgerActor

    @State private var selectedDeckFilter: DeckFilter?
    @State private var activeTab: DeckTab = .months
    @State private var isShowingSettingsSheet = false

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

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        // 1. Minimal Top Bar
                        topHeaderBar

                        // 2. Hero Primary Action Card (Recent Photos / Quick Triage)
                        primaryQuickStartCard

                        // 3. Clean Segmented Tab Bar (Months | Categories | Albums)
                        tabSelectorBar

                        // 4. Active Tab Content
                        tabContentSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(item: $selectedDeckFilter) { filter in
                SwipeDeckView(
                    filter: filter,
                    includePreviouslyKept: dashboardVM.includePreviouslyKept,
                    ledger: ledger,
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
            .sheet(isPresented: $isShowingSettingsSheet) {
                dashboardSettingsSheet
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

    // MARK: - 1. Minimal Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SwipeDeck")
                    .font(SwipeDeckTypography.roundedTitle(28, weight: .heavy))
                    .foregroundStyle(SwipeDeckTheme.textPrimary)

                if dashboardVM.lifetimeStats.totalBytesReclaimed > 0 {
                    Text("\(dashboardVM.lifetimeStats.formattedBytesReclaimed) freed so far")
                        .exifMonoStyle(size: 11, color: SwipeDeckTheme.accentKeep)
                } else {
                    Text("Pick a deck to start swiping")
                        .font(SwipeDeckTypography.body(13))
                        .foregroundStyle(SwipeDeckTheme.textSecondary)
                }
            }

            Spacer()

            TrashPillButton(
                count: trashVM.stagedCount,
                formattedBytes: trashVM.formattedTotalStagedSize
            ) {
                trashVM.isPresentingCommitSheet = true
            }

            Button {
                isShowingSettingsSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SwipeDeckTheme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(SwipeDeckTheme.surfaceElevated, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 2. Hero Primary Action Card

    private var primaryQuickStartCard: some View {
        Button {
            selectedDeckFilter = .allPhotos
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("START SWIPING")
                        .exifMonoStyle(size: 11, color: SwipeDeckTheme.accentKeep)

                    Text("Recent Camera Roll")
                        .font(SwipeDeckTypography.roundedTitle(22, weight: .bold))
                        .foregroundStyle(SwipeDeckTheme.textPrimary)

                    Text("Jump straight into your latest photos & videos.")
                        .font(SwipeDeckTypography.body(13))
                        .foregroundStyle(SwipeDeckTheme.textSecondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(SwipeDeckTheme.accentKeep)
                        .frame(width: 48, height: 48)
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SwipeDeckTheme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(SwipeDeckTheme.accentKeep.opacity(0.45), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Segmented Tab Bar

    private var tabSelectorBar: some View {
        HStack(spacing: 8) {
            ForEach(DeckTab.allCases) { tab in
                let isSelected = activeTab == tab
                Button {
                    HapticEngine.shared.fireSelectionTick()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        activeTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(SwipeDeckTypography.roundedHeadline(14, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .black : SwipeDeckTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(isSelected ? SwipeDeckTheme.textPrimary : SwipeDeckTheme.surfaceElevated)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 4. Tab Content Section

    @ViewBuilder
    private var tabContentSection: some View {
        switch activeTab {
        case .months:
            monthsSectionView

        case .quickClean:
            categoriesSectionView

        case .albums:
            albumsSectionView
        }
    }

    private var monthsSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Select a month to declutter")
                    .font(SwipeDeckTypography.body(13))
                    .foregroundStyle(SwipeDeckTheme.textSecondary)
                Spacer()
                Button {
                    dashboardVM.isPresentingCustomDateRangeSheet = true
                } label: {
                    Label("Custom Dates", systemImage: "calendar")
                        .font(SwipeDeckTypography.roundedCounter(13))
                        .foregroundStyle(SwipeDeckTheme.accentDefer)
                }
                .buttonStyle(.plain)
            }

            if dashboardVM.isLoading && dashboardVM.monthDecks.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(SwipeDeckTheme.accentKeep)
                    Spacer()
                }
                .padding(.vertical, 36)
            } else if dashboardVM.monthDecks.isEmpty {
                emptySectionPlaceholder(text: "No monthly photo groups found yet.")
            } else {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(dashboardVM.monthDecks) { monthSummary in
                        MonthBucketCardView(summary: monthSummary) {
                            selectedDeckFilter = monthSummary.filter
                        }
                    }
                }
            }
        }
    }

    private var categoriesSectionView: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(dashboardVM.sourceDecks.filter { $0.filter != .allPhotos }) { summary in
                DeckSummaryCardView(summary: summary) {
                    selectedDeckFilter = summary.filter
                }
            }
        }
    }

    private var albumsSectionView: some View {
        Group {
            if dashboardVM.userAlbumDecks.isEmpty {
                emptySectionPlaceholder(text: "No custom albums found in your Photo Library.")
            } else {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(dashboardVM.userAlbumDecks) { albumSummary in
                        DeckSummaryCardView(summary: albumSummary) {
                            selectedDeckFilter = albumSummary.filter
                        }
                    }
                }
            }
        }
    }

    private func emptySectionPlaceholder(text: String) -> some View {
        Text(text)
            .font(SwipeDeckTypography.body(14))
            .foregroundStyle(SwipeDeckTheme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    // MARK: - Settings & Stats Sheet

    private var dashboardSettingsSheet: some View {
        NavigationStack {
            ZStack {
                SwipeDeckTheme.backgroundPrimary.ignoresSafeArea()
                VStack(spacing: 18) {
                    Toggle(isOn: $dashboardVM.includePreviouslyKept) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Include Previously Kept Photos")
                                .font(SwipeDeckTypography.roundedHeadline(16, weight: .semibold))
                                .foregroundStyle(SwipeDeckTheme.textPrimary)
                            Text("Turn on to re-review photos you already swiped right on.")
                                .font(SwipeDeckTypography.body(13))
                                .foregroundStyle(SwipeDeckTheme.textSecondary)
                        }
                    }
                    .tint(SwipeDeckTheme.accentKeep)
                    .padding(16)
                    .background(SwipeDeckTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TOTAL RECLAIMED")
                                .exifMonoStyle(size: 10, color: SwipeDeckTheme.textSecondary)
                            Text(dashboardVM.lifetimeStats.formattedBytesReclaimed)
                                .font(SwipeDeckTypography.roundedTitle(22, weight: .bold))
                                .foregroundStyle(SwipeDeckTheme.accentKeep)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(dashboardVM.lifetimeStats.totalItemsDeleted) trashed")
                                .exifMonoStyle(size: 12, color: SwipeDeckTheme.accentDelete)
                            Text("\(dashboardVM.lifetimeStats.totalAssetsKept) kept")
                                .exifMonoStyle(size: 12, color: SwipeDeckTheme.accentKeep)
                        }
                    }
                    .padding(16)
                    .background(SwipeDeckTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Preferences & Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingSettingsSheet = false
                    }
                    .foregroundStyle(SwipeDeckTheme.accentKeep)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}

// MARK: - Supporting Deck Cards

private struct DeckSummaryCardView: View {
    let summary: DeckSummaryItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: summary.filter.systemIcon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(summary.filter == .heavyHitters ? SwipeDeckTheme.accentUndo : SwipeDeckTheme.accentKeep)
                        .frame(width: 34, height: 34)
                        .background(
                            (summary.filter == .heavyHitters ? SwipeDeckTheme.accentUndo : SwipeDeckTheme.accentKeep).opacity(0.14),
                            in: Circle()
                        )

                    Spacer()

                    Text("\(summary.unreviewedCount)")
                        .roundedStatStyle(size: 14, color: SwipeDeckTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.filter.title)
                        .font(SwipeDeckTypography.roundedHeadline(15, weight: .bold))
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
                    .frame(height: 148)

                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 148)
                        .clipped()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.filter.title)
                        .font(SwipeDeckTypography.roundedHeadline(15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(summary.unreviewedCount) photos")
                        .exifMonoStyle(size: 11, color: SwipeDeckTheme.accentKeep)
                }
                .padding(12)
            }
            .frame(height: 148)
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
                pointSize: CGSize(width: 170, height: 148)
            ) { image in
                self.coverImage = image
            }
        }
    }
}
