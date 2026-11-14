import SwiftUI

/// Allows the user to configure a Custom Date Range deck (PRD Section 4.1 "By Timeframe").
public struct CustomDateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var endDate: Date = .now

    public let onSelectRange: (DeckFilter) -> Void

    public init(onSelectRange: @escaping (DeckFilter) -> Void) {
        self.onSelectRange = onSelectRange
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                SwipeDeckTheme.backgroundPrimary
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("SELECT WINDOW")
                            .exifMonoStyle(size: 11, color: SwipeDeckTheme.textSecondary)

                        DatePicker(
                            "From Date",
                            selection: $startDate,
                            in: ...endDate,
                            displayedComponents: [.date]
                        )
                        .font(SwipeDeckTypography.roundedHeadline(16))
                        .foregroundStyle(SwipeDeckTheme.textPrimary)

                        Divider()
                            .overlay(SwipeDeckTheme.borderSubtle)

                        DatePicker(
                            "To Date",
                            selection: $endDate,
                            in: startDate...Date.now,
                            displayedComponents: [.date]
                        )
                        .font(SwipeDeckTypography.roundedHeadline(16))
                        .foregroundStyle(SwipeDeckTheme.textPrimary)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(SwipeDeckTheme.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
                            )
                    )

                    Spacer()

                    Button {
                        let filter = DeckFilter.customDateRange(start: startDate, end: endDate)
                        dismiss()
                        onSelectRange(filter)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Start Custom Range Deck")
                                .font(SwipeDeckTypography.roundedHeadline(17, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(SwipeDeckTheme.accentKeep, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationTitle("Custom Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(SwipeDeckTheme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
