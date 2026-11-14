import SwiftUI

/// Renders the cute animated SwipeDeck companion mascot ("Pebble") that morphs and grows
/// across 5 evolutionary stages based on total app usage.
public struct CompanionAvatarView: View {
    public let progress: AvatarCompanionProgress
    public var containerSize: CGFloat = 68
    public var isInteractive: Bool = true

    @State private var isBreathing = false
    @State private var isBouncing = false

    public init(
        progress: AvatarCompanionProgress,
        containerSize: CGFloat = 68,
        isInteractive: Bool = true
    ) {
        self.progress = progress
        self.containerSize = containerSize
        self.isInteractive = isInteractive
    }

    private var stage: AvatarCompanionProgress.Stage {
        progress.stage
    }

    public var body: some View {
        let baseCreatureSize = containerSize * 0.62 * stage.visualScale

        ZStack {
            // Subtle progress ring around the habitat circle
            Circle()
                .stroke(SwipeDeckTheme.surfaceSecondary, lineWidth: 3.5)
                .frame(width: containerSize, height: containerSize)

            Circle()
                .trim(from: 0, to: progress.progressToNextStage)
                .stroke(
                    AngularGradient(
                        colors: [stage.primaryColor, stage.secondaryColor, stage.primaryColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: containerSize, height: containerSize)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress.progressToNextStage)

            // Ambient aura for higher evolution stages (Guardian & Cosmic)
            if stage.rawValue >= 4 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [stage.primaryColor.opacity(0.38), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: containerSize * 0.55
                        )
                    )
                    .frame(width: containerSize * 1.1, height: containerSize * 1.1)
                    .scaleEffect(isBreathing ? 1.08 : 0.94)
            }

            // Morphing Creature Body + Accessories
            ZStack {
                // Stage 3+ Cute Side Ears / Winglets
                if stage.rawValue >= 3 {
                    HStack(spacing: baseCreatureSize * 0.72) {
                        Ellipse()
                            .fill(stage.secondaryColor)
                            .frame(width: baseCreatureSize * 0.28, height: baseCreatureSize * 0.42)
                            .rotationEffect(.degrees(-28))
                        Ellipse()
                            .fill(stage.secondaryColor)
                            .frame(width: baseCreatureSize * 0.28, height: baseCreatureSize * 0.42)
                            .rotationEffect(.degrees(28))
                    }
                }

                // Main Squishy Blob Body
                RoundedRectangle(
                    cornerRadius: stage.rawValue >= 3 ? baseCreatureSize * 0.44 : baseCreatureSize * 0.5,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [stage.primaryColor, stage.secondaryColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: baseCreatureSize, height: baseCreatureSize * 0.92)
                .overlay(
                    // Glossy highlight on top-left of creature
                    Ellipse()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: baseCreatureSize * 0.42, height: baseCreatureSize * 0.20)
                        .offset(x: -baseCreatureSize * 0.14, y: -baseCreatureSize * 0.24)
                        .rotationEffect(.degrees(-18))
                )
                .shadow(color: stage.primaryColor.opacity(0.45), radius: 8, y: 3)

                // Top Head Accessory (Sprout leaf -> Antenna -> Crown -> Cosmic Halo)
                headAccessory(for: stage, size: baseCreatureSize)
                    .offset(y: -baseCreatureSize * 0.54)

                // Expressive Face (Eyes, Cheeks, Smile)
                creatureFace(for: stage, size: baseCreatureSize)
                    .offset(y: baseCreatureSize * 0.04)
            }
            .scaleEffect(
                x: isBouncing ? 1.14 : (isBreathing ? 1.03 : 0.97),
                y: isBouncing ? 0.86 : (isBreathing ? 0.97 : 1.03)
            )
            .offset(y: isBouncing ? -5 : 0)
        }
        .contentShape(Circle())
        .onTapGesture {
            guard isInteractive else { return }
            HapticEngine.shared.fireSelectionTick()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
                isBouncing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
                    isBouncing = false
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    // MARK: - Evolutionary Accessories & Face

    @ViewBuilder
    private func headAccessory(for stage: AvatarCompanionProgress.Stage, size: CGFloat) -> some View {
        switch stage {
        case .sprout:
            Image(systemName: "leaf.fill")
                .font(.system(size: max(10, size * 0.34), weight: .bold))
                .foregroundStyle(Color(red: 0.45, green: 0.95, blue: 0.55))
        case .pebble:
            Circle()
                .fill(stage.primaryColor)
                .frame(width: size * 0.22, height: size * 0.22)
        case .buddy:
            Image(systemName: "sparkles")
                .font(.system(size: max(11, size * 0.34), weight: .bold))
                .foregroundStyle(SwipeDeckTheme.accentUndo)
        case .guardian:
            Image(systemName: "crown.fill")
                .font(.system(size: max(12, size * 0.36), weight: .bold))
                .foregroundStyle(SwipeDeckTheme.accentUndo)
        case .cosmic:
            ZStack {
                Ellipse()
                    .strokeBorder(SwipeDeckTheme.accentUndo, lineWidth: 2.2)
                    .frame(width: size * 0.75, height: size * 0.22)
                Image(systemName: "sparkle")
                    .font(.system(size: max(11, size * 0.30), weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: -4)
            }
        }
    }

    @ViewBuilder
    private func creatureFace(for stage: AvatarCompanionProgress.Stage, size: CGFloat) -> some View {
        let eyeSize = max(4.0, size * 0.14)
        let cheekSize = max(4.5, size * 0.16)

        VStack(spacing: size * 0.05) {
            // Eyes + Rosy Cheeks
            HStack(spacing: size * 0.24) {
                ZStack(alignment: .topLeading) {
                    Circle()
                        .fill(Color.black.opacity(0.88))
                        .frame(width: eyeSize, height: eyeSize)
                    Circle()
                        .fill(Color.white)
                        .frame(width: eyeSize * 0.38, height: eyeSize * 0.38)
                        .offset(x: eyeSize * 0.15, y: eyeSize * 0.15)
                }

                ZStack(alignment: .topLeading) {
                    Circle()
                        .fill(Color.black.opacity(0.88))
                        .frame(width: eyeSize, height: eyeSize)
                    Circle()
                        .fill(Color.white)
                        .frame(width: eyeSize * 0.38, height: eyeSize * 0.38)
                        .offset(x: eyeSize * 0.15, y: eyeSize * 0.15)
                }
            }

            // Rosy cheeks + happy mouth
            HStack(spacing: size * 0.16) {
                Circle()
                    .fill(Color.pink.opacity(0.55))
                    .frame(width: cheekSize, height: cheekSize * 0.65)

                // Cute curved smile
                Capsule()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: size * 0.18, height: max(2.5, size * 0.07))

                Circle()
                    .fill(Color.pink.opacity(0.55))
                    .frame(width: cheekSize, height: cheekSize * 0.65)
            }
        }
    }
}
