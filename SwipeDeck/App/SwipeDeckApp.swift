import SwiftUI
import SwiftData

/// Main entry point for SwipeDeck (iOS 17.0+, Swift 6).
/// Configures the SwiftData `ModelContainer`, initializes the background `LedgerActor`,
/// and gates access behind `PhotoLibraryAuthorizationService`.
@main
public struct SwipeDeckApp: App {
    private let modelContainer: ModelContainer
    private let ledgerActor: LedgerActor

    @State private var authService = PhotoLibraryAuthorizationService()
    @State private var dashboardVM: DashboardViewModel
    @State private var trashVM: TrashStagingViewModel

    public init() {
        do {
            let schema = Schema([
                ReviewedAssetRecord.self,
                DeckSessionCheckpoint.self,
                LifetimeStatsRecord.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let ledger = LedgerActor(modelContainer: container)

            self.modelContainer = container
            self.ledgerActor = ledger
            self._dashboardVM = State(initialValue: DashboardViewModel(ledger: ledger))
            self._trashVM = State(initialValue: TrashStagingViewModel(ledger: ledger))
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }

    public var body: some Scene {
        WindowGroup {
            Group {
                switch authService.accessState {
                case .authorized, .limited:
                    HomeDashboardView(
                        dashboardVM: dashboardVM,
                        trashVM: trashVM,
                        ledger: ledgerActor
                    )
                case .notDetermined, .denied:
                    PhotoPermissionGateView(authService: authService)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                authService.refreshStatus()
            }
        }
        .modelContainer(modelContainer)
    }
}

/// Onboarding & permission gate screen shown when PhotoKit access is `.notDetermined` or `.denied`.
private struct PhotoPermissionGateView: View {
    @Bindable var authService: PhotoLibraryAuthorizationService

    var body: some View {
        ZStack {
            SwipeDeckTheme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(SwipeDeckTheme.accentKeep.opacity(0.15))
                        .frame(width: 96, height: 96)
                    Image(systemName: "rectangle.stack.badge.play")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(SwipeDeckTheme.accentKeep)
                }

                VStack(spacing: 10) {
                    Text("Welcome to SwipeDeck")
                        .font(SwipeDeckTypography.roundedTitle(28, weight: .heavy))
                        .foregroundStyle(SwipeDeckTheme.textPrimary)

                    Text("Declutter your camera roll one card at a time. Swipe right to keep, left to stage for deletion, up to defer, or down to undo.")
                        .font(SwipeDeckTypography.body(15))
                        .foregroundStyle(SwipeDeckTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                VStack(alignment: .leading, spacing: 14) {
                    featureBullet(
                        icon: "bolt.shield.fill",
                        color: SwipeDeckTheme.accentKeep,
                        title: "Two-Stage Safety Net",
                        subtitle: "Nothing is deleted immediately. Review your staged trash bin and commit in one tap."
                    )
                    featureBullet(
                        icon: "lock.fill",
                        color: SwipeDeckTheme.accentDefer,
                        title: "100% On-Device Privacy",
                        subtitle: "Your photos never leave your iPhone."
                    )
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(SwipeDeckTheme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)

                Spacer()

                if authService.accessState == .denied {
                    Button {
                        authService.openSystemSettings()
                    } label: {
                        Text("Open iOS Settings to Grant Access")
                            .font(SwipeDeckTypography.roundedHeadline(17, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(SwipeDeckTheme.accentUndo, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                } else {
                    Button {
                        authService.requestAccess()
                    } label: {
                        HStack(spacing: 8) {
                            if authService.isRequestingPermission {
                                ProgressView()
                                    .tint(.black)
                            }
                            Text("Allow Photo Library Access")
                                .font(SwipeDeckTypography.roundedHeadline(17, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(SwipeDeckTheme.accentKeep, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(authService.isRequestingPermission)
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func featureBullet(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SwipeDeckTypography.roundedHeadline(15, weight: .bold))
                    .foregroundStyle(SwipeDeckTheme.textPrimary)
                Text(subtitle)
                    .font(SwipeDeckTypography.body(13))
                    .foregroundStyle(SwipeDeckTheme.textSecondary)
            }
        }
    }
}
