import SwiftUI

/// Main Triage View implementing the One-Handed Ergonomic Layout (PRD Section 3.1 & Section 6.2):
/// - Top Bar (Minimal): Back button, Deck Progress Bar (`142 / 300`), and Interactive Trash Staging Pill (`🗑️ 28 • 145 MB`).
/// - Center Canvas (82% Screen Height): 3-card ZStack with depth scaling (`1.0`, `0.95`, `0.90`).
/// - Bottom Action Dock (10% Screen Height): Four circular glassmorphic buttons (`Undo`, `Trash`, `Skip`, `Keep`).
public struct SwipeDeckView: View {
    @Environment(\.dismiss) private var dismiss
    public let filter: DeckFilter
    public let includePreviouslyKept: Bool
    public let ledger: LedgerActor
    @Bindable public var trashVM: TrashStagingViewModel
    public let onSessionEnded: () -> Void

    @State private var sessionVM: DeckSessionViewModel
    @State private var activeDragProgress: CGFloat = 0.0

    public init(
        filter: DeckFilter,
        includePreviouslyKept: Bool,
        ledger: LedgerActor,
        trashVM: TrashStagingViewModel,
        onSessionEnded: @escaping () -> Void
    ) {
        self.filter = filter
        self.includePreviouslyKept = includePreviouslyKept
        self.ledger = ledger
        self.trashVM = trashVM
        self.onSessionEnded = onSessionEnded
        self._sessionVM = State(
            initialValue: DeckSessionViewModel(
                filter: filter,
                includePreviouslyKept: includePreviouslyKept,
                ledger: ledger,
                trashVM: trashVM
            )
        )
    }

    public var body: some View {
        GeometryReader { screenGeo in
            ZStack {
                SwipeDeckTheme.backgroundPrimary
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    // 1. Minimal Top Bar
                    topNavigationBar

                    // 2. Center Canvas (~82% Screen Height)
                    ZStack {
                        if sessionVM.isLoading {
                            loadingStateView
                        } else if sessionVM.isDeckFinished {
                            deckCompletedStateView
                        } else {
                            cardStackCanvas
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: screenGeo.size.height * 0.78)
                    .padding(.horizontal, 12)

                    Spacer(minLength: 0)

                    // 3. Bottom Action Dock (~10% Screen Height)
                    BottomActionDockView(
                        canUndo: sessionVM.canUndo,
                        isEnabled: !sessionVM.isDeckFinished && !sessionVM.isLoading
                    ) { action in
                        withAnimation(.spring(response: SwipeDeckTheme.springResponse, dampingFraction: SwipeDeckTheme.springDamping)) {
                            sessionVM.performAction(action)
                        }
                    }
                    .frame(height: max(76, screenGeo.size.height * 0.10))
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await sessionVM.loadSession()
        }
        .onDisappear {
            sessionVM.cleanupOnDisappear()
            onSessionEnded()
        }
    }

    // MARK: - Top Bar (Back Button, Progress Pill, Trash Staging Pill)

    private var topNavigationBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    if trashVM.stagedCount > 0 {
                        trashVM.isPresentingCommitSheet = true
                    } else {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                        Text(sessionVM.filter.title)
                            .font(SwipeDeckTypography.roundedHeadline(15, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(SwipeDeckTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(SwipeDeckTheme.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // Deck Progress Counter (e.g., 142 / 300)
                if !sessionVM.isLoading && sessionVM.totalCount > 0 {
                    Text("\(sessionVM.progressDisplayIndex) / \(sessionVM.totalCount)")
                        .roundedStatStyle(size: 13, color: SwipeDeckTheme.textSecondary)
                        .contentTransition(.numericText())
                }

                Spacer()

                // Interactive Trash Staging Pill (🗑️ 28 • 145 MB)
                TrashPillButton(
                    count: trashVM.stagedCount,
                    formattedBytes: trashVM.formattedTotalStagedSize
                ) {
                    trashVM.isPresentingCommitSheet = true
                }
            }
            .padding(.horizontal, 16)

            // Thin Progress Bar
            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SwipeDeckTheme.surfaceElevated)
                        .frame(height: 3)
                    Capsule()
                        .fill(SwipeDeckTheme.accentKeep)
                        .frame(width: barGeo.size.width * sessionVM.progressFraction, height: 3)
                        .animation(.easeOut(duration: 0.2), value: sessionVM.progressFraction)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 16)
        }
        .padding(.top, 4)
    }

    // MARK: - 3-Card Stack Canvas

    private var cardStackCanvas: some View {
        ZStack {
            // Render back-to-front so stackDepth 0 (top card) is on top of the ZStack
            ForEach(sessionVM.visibleStackCards.reversed(), id: \.asset.id) { item in
                SwipeCardView(
                    asset: item.asset,
                    stackDepth: item.stackDepth,
                    activeDragProgress: activeDragProgress,
                    isMetadataVisible: sessionVM.isMetadataOverlayVisible,
                    metadata: sessionVM.activeCardMetadata,
                    isAudioMuted: $sessionVM.isAudioMuted,
                    canUndo: sessionVM.canUndo,
                    onDragProgressChange: { progress in
                        activeDragProgress = progress
                    },
                    onSingleTap: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            sessionVM.toggleMetadataOverlay()
                        }
                    },
                    onCommitAction: { action in
                        sessionVM.performAction(action)
                    }
                )
                .zIndex(Double(10 - item.stackDepth))
            }
        }
    }

    // MARK: - Loading & Empty/Completed States

    private var loadingStateView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(SwipeDeckTheme.accentKeep)
                .scaleEffect(1.2)
            Text("Preparing \(sessionVM.filter.title) Deck…")
                .font(SwipeDeckTypography.roundedHeadline(16))
                .foregroundStyle(SwipeDeckTheme.textSecondary)
        }
    }

    private var deckCompletedStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(SwipeDeckTheme.accentKeep.opacity(0.15))
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(SwipeDeckTheme.accentKeep)
            }

            VStack(spacing: 8) {
                Text("Deck Complete!")
                    .font(SwipeDeckTypography.roundedTitle(26))
                    .foregroundStyle(SwipeDeckTheme.textPrimary)

                Text(
                    sessionVM.totalCount == 0
                        ? "All photos in \(sessionVM.filter.title) have already been reviewed."
                        : "You triaged all \(sessionVM.totalCount) items in this deck."
                )
                .font(SwipeDeckTypography.body(15))
                .foregroundStyle(SwipeDeckTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            }

            if trashVM.stagedCount > 0 {
                Button {
                    trashVM.isPresentingCommitSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                        Text("Review & Delete \(trashVM.stagedCount) Items (\(trashVM.formattedTotalStagedSize))")
                            .font(SwipeDeckTypography.roundedHeadline(16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(SwipeDeckTheme.accentDelete, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                dismiss()
            } label: {
                Text("Back to Decks")
                    .font(SwipeDeckTypography.roundedHeadline(15))
                    .foregroundStyle(SwipeDeckTheme.textSecondary)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: SwipeDeckTheme.cardCornerRadius, style: .continuous)
                .fill(SwipeDeckTheme.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: SwipeDeckTheme.cardCornerRadius, style: .continuous)
                        .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
                )
        )
    }
}
