import SwiftUI
import Photos

/// Single triage card view engineered for 120Hz ProMotion gesture physics (PRD Section 3.1, 6.2, 6.3, 7):
/// - Aspect-fit full-screen container so the entire photo/video is visible without cropping.
/// - Pinch-to-zoom with automatic snap-back on release and high-resolution bitmap upgrade past 200% zoom.
/// - 4-directional swipe recognition with semantic border glows, stamp badges, and threshold haptics.
public struct SwipeCardView: View {
    public let asset: MediaAsset
    public let stackDepth: Int // 0 = active top card, 1 = second card, 2 = third card
    public let activeDragProgress: CGFloat // [0.0 ... 1.0] from top card to interpolate background card scale
    public let isMetadataVisible: Bool
    public let metadata: AssetMetadata?
    @Binding public var isAudioMuted: Bool
    public let canUndo: Bool
    public let onDragProgressChange: (CGFloat) -> Void
    public let onSingleTap: () -> Void
    public let onCommitAction: (SwipeAction) -> Void

    @State private var displayImage: UIImage?
    @State private var highResZoomImage: UIImage?
    @State private var isStreamingFromiCloud = false
    @State private var imageRequestID: PHImageRequestID?

    // Gesture states
    @State private var dragOffset: CGSize = .zero
    @State private var zoomScale: CGFloat = 1.0
    @State private var hasRequestedHighResZoom = false

    private var isTopCard: Bool { stackDepth == 0 }

    public init(
        asset: MediaAsset,
        stackDepth: Int,
        activeDragProgress: CGFloat,
        isMetadataVisible: Bool,
        metadata: AssetMetadata?,
        isAudioMuted: Binding<Bool>,
        canUndo: Bool,
        onDragProgressChange: @escaping (CGFloat) -> Void,
        onSingleTap: @escaping () -> Void,
        onCommitAction: @escaping (SwipeAction) -> Void
    ) {
        self.asset = asset
        self.stackDepth = stackDepth
        self.activeDragProgress = activeDragProgress
        self.isMetadataVisible = isMetadataVisible
        self.metadata = metadata
        self._isAudioMuted = isAudioMuted
        self.canUndo = canUndo
        self.onDragProgressChange = onDragProgressChange
        self.onSingleTap = onSingleTap
        self.onCommitAction = onCommitAction
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Card Base Container
                RoundedRectangle(cornerRadius: SwipeDeckTheme.cardCornerRadius, style: .continuous)
                    .fill(SwipeDeckTheme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: SwipeDeckTheme.cardCornerRadius, style: .continuous)
                            .strokeBorder(activeBorderColor, lineWidth: activeBorderWidth)
                    )
                    .shadow(
                        color: activeGlowColor.opacity(Double(min(1.0, currentThresholdProgress * 0.65))),
                        radius: 22,
                        y: 6
                    )

                // Media Content (Aspect-Fit Image or Muted Autoplay Video)
                ZStack {
                    if isTopCard && asset.kind == .video {
                        LivePhotoVideoPlayerView(asset: asset, isAudioMuted: $isAudioMuted)
                    } else if let image = highResZoomImage ?? displayImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(isTopCard ? zoomScale : 1.0)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: SwipeDeckTheme.cardCornerRadius, style: .continuous))

                // Subtle iCloud streaming spinner when zooming in on an uncached asset (PRD Section 7)
                if isTopCard && isStreamingFromiCloud && zoomScale > 1.05 {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.75)
                                Image(systemName: "icloud.and.arrow.down")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(16)
                        Spacer()
                    }
                }

                // Media Kind & File Size Badge (Bottom-Left when not playing video)
                if asset.kind != .video {
                    VStack {
                        Spacer()
                        HStack {
                            if asset.kind == .livePhoto {
                                Label("LIVE", systemImage: "livephoto")
                                    .exifMonoStyle(size: 11, color: .white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            Spacer()
                        }
                        .padding(14)
                    }
                }

                // Single-Tap Technical Metadata Overlay (PRD Section 3.1)
                if isTopCard && isMetadataVisible {
                    VStack {
                        MetadataOverlayView(asset: asset, metadata: metadata)
                        Spacer()
                    }
                }

                // 4-Directional Semantic Action Badge Overlay (Keep, Trash, Defer Up, Undo Down)
                if isTopCard, let candidate = activeCandidateAction, currentThresholdProgress > 0.18 {
                    semanticStampBadge(for: candidate, progress: currentThresholdProgress)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(cardScale)
            .offset(x: isTopCard ? dragOffset.width : 0, y: isTopCard ? dragOffset.height : backgroundVerticalOffset)
            .rotationEffect(
                .degrees(isTopCard ? Double(dragOffset.width / 22.0) : 0),
                anchor: .bottom
            )
            .contentShape(RoundedRectangle(cornerRadius: SwipeDeckTheme.cardCornerRadius, style: .continuous))
            .onTapGesture {
                guard isTopCard else { return }
                onSingleTap()
            }
            .gesture(isTopCard ? dragGesture(in: geo.size) : nil)
            .simultaneousGesture(isTopCard ? magnificationGesture : nil)
        }
        .task(id: asset.id) {
            loadScreenSizeImage()
        }
        .onDisappear {
            AssetPrefetchPipeline.shared.cancelRequest(imageRequestID)
        }
    }

    // MARK: - 3D Stack Depth & Scale Calculations (PRD Section 6.2)

    private var cardScale: CGFloat {
        switch stackDepth {
        case 0:
            // Subtle shrink animation when swiping Up to push to back of stack (PRD Section 3.1)
            if activeCandidateAction == .deferToBack {
                let shrink = min(0.12, max(0, -dragOffset.height / 900.0))
                return 1.0 - shrink
            }
            return 1.0
        case 1:
            return 0.95 + (0.05 * activeDragProgress)
        default:
            return 0.90 + (0.05 * activeDragProgress)
        }
    }

    private var backgroundVerticalOffset: CGFloat {
        switch stackDepth {
        case 0:
            return 0
        case 1:
            return 14.0 * (1.0 - activeDragProgress)
        default:
            return 28.0 * (1.0 - activeDragProgress)
        }
    }

    // MARK: - Gesture Classification & Semantic Styling

    private var activeCandidateAction: SwipeAction? {
        let dx = dragOffset.width
        let dy = dragOffset.height
        guard abs(dx) > 8 || abs(dy) > 8 else { return nil }

        if abs(dx) >= abs(dy) {
            return dx > 0 ? .keep : .trash
        } else {
            if dy < 0 {
                return .deferToBack
            } else {
                return canUndo ? .undo : nil
            }
        }
    }

    private var currentThresholdProgress: CGFloat {
        guard let candidate = activeCandidateAction else { return 0 }
        switch candidate {
        case .keep, .trash:
            return min(1.3, abs(dragOffset.width) / SwipeDeckTheme.horizontalSwipeThreshold)
        case .deferToBack, .undo:
            return min(1.3, abs(dragOffset.height) / SwipeDeckTheme.verticalSwipeThreshold)
        }
    }

    private var activeGlowColor: Color {
        guard isTopCard, let candidate = activeCandidateAction else { return .clear }
        switch candidate {
        case .keep:
            return SwipeDeckTheme.accentKeep
        case .trash:
            return SwipeDeckTheme.accentDelete
        case .deferToBack:
            return SwipeDeckTheme.accentDefer
        case .undo:
            return SwipeDeckTheme.accentUndo
        }
    }

    private var activeBorderColor: Color {
        guard isTopCard, let candidate = activeCandidateAction, currentThresholdProgress > 0.15 else {
            return SwipeDeckTheme.borderSubtle
        }
        return activeGlowColor.opacity(Double(min(1.0, currentThresholdProgress)))
    }

    private var activeBorderWidth: CGFloat {
        guard isTopCard, currentThresholdProgress > 0.15 else { return 1.0 }
        return 1.0 + (2.5 * min(1.0, currentThresholdProgress))
    }

    // MARK: - Drag & Pinch-to-Zoom Gestures

    private func dragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard zoomScale <= 1.02 else { return }
                dragOffset = value.translation

                let progress = min(1.0, currentThresholdProgress)
                onDragProgressChange(progress)

                // Trigger light haptic the exact millisecond the dragged card crosses the threshold (PRD Section 6.3)
                let isAboveThreshold = currentThresholdProgress >= 1.0
                HapticEngine.shared.evaluateDragThreshold(isAboveThreshold: isAboveThreshold)
            }
            .onEnded { value in
                HapticEngine.shared.resetThresholdState()
                let predicted = value.predictedEndTranslation
                let dx = value.translation.width
                let dy = value.translation.height

                // Determine if either actual translation or high-velocity flick crossed commit threshold
                let committedAction: SwipeAction? = {
                    if abs(dx) >= abs(dy) {
                        if dx >= SwipeDeckTheme.horizontalSwipeThreshold || predicted.width >= SwipeDeckTheme.horizontalSwipeThreshold * 1.45 {
                            return .keep
                        }
                        if dx <= -SwipeDeckTheme.horizontalSwipeThreshold || predicted.width <= -SwipeDeckTheme.horizontalSwipeThreshold * 1.45 {
                            return .trash
                        }
                    } else {
                        if dy <= -SwipeDeckTheme.verticalSwipeThreshold || predicted.height <= -SwipeDeckTheme.verticalSwipeThreshold * 1.45 {
                            return .deferToBack
                        }
                        if canUndo && (dy >= SwipeDeckTheme.verticalSwipeThreshold || predicted.height >= SwipeDeckTheme.verticalSwipeThreshold * 1.45) {
                            return .undo
                        }
                    }
                    return nil
                }()

                if let action = committedAction {
                    executeFlyOffAndCommit(action: action, containerSize: containerSize)
                } else {
                    // Critically damped snap-back spring (response: 0.32, dampingFraction: 0.78)
                    withAnimation(.spring(response: SwipeDeckTheme.springResponse, dampingFraction: SwipeDeckTheme.springDamping)) {
                        dragOffset = .zero
                        onDragProgressChange(0)
                    }
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let clamped = min(4.5, max(1.0, scale))
                zoomScale = clamped

                // PRD Section 7: Only decode full high-res buffer if user pinches past 200% zoom
                if clamped >= 2.0 && !hasRequestedHighResZoom {
                    hasRequestedHighResZoom = true
                    AssetPrefetchPipeline.shared.requestCardImage(
                        for: asset.id,
                        highResolutionForZoom: true
                    ) { highRes, inCloud in
                        self.isStreamingFromiCloud = inCloud
                        if let highRes {
                            self.highResZoomImage = highRes
                        }
                    }
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: SwipeDeckTheme.springResponse, dampingFraction: SwipeDeckTheme.springDamping)) {
                    zoomScale = 1.0
                }
                // Release raw high-res buffer once snapped back to 1.0x to respect memory ceiling
                highResZoomImage = nil
                hasRequestedHighResZoom = false
            }
    }

    private func executeFlyOffAndCommit(action: SwipeAction, containerSize: CGSize) {
        if action == .undo {
            withAnimation(.spring(response: SwipeDeckTheme.springResponse, dampingFraction: SwipeDeckTheme.springDamping)) {
                dragOffset = .zero
                onDragProgressChange(0)
            }
            onCommitAction(.undo)
            return
        }

        let targetOffset: CGSize
        switch action {
        case .keep:
            targetOffset = CGSize(width: containerSize.width * 1.35, height: dragOffset.height * 0.4)
        case .trash:
            targetOffset = CGSize(width: -containerSize.width * 1.35, height: dragOffset.height * 0.4)
        case .deferToBack:
            targetOffset = CGSize(width: 0, height: -containerSize.height * 1.15)
        case .undo:
            targetOffset = .zero
        }

        withAnimation(.spring(response: SwipeDeckTheme.springResponse, dampingFraction: SwipeDeckTheme.springDamping)) {
            dragOffset = targetOffset
            onDragProgressChange(1.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            dragOffset = .zero
            onDragProgressChange(0)
            onCommitAction(action)
        }
    }

    // MARK: - Semantic Stamp Badge UI

    @ViewBuilder
    private func semanticStampBadge(for action: SwipeAction, progress: CGFloat) -> some View {
        let opacity = Double(min(1.0, (progress - 0.15) / 0.65))
        let config: (title: String, icon: String, color: Color, alignment: Alignment) = {
            switch action {
            case .keep:
                return ("KEEP", "checkmark.circle.fill", SwipeDeckTheme.accentKeep, .topLeading)
            case .trash:
                return ("TRASH", "trash.circle.fill", SwipeDeckTheme.accentDelete, .topTrailing)
            case .deferToBack:
                return ("LATER", "arrow.up.circle.fill", SwipeDeckTheme.accentDefer, .bottom)
            case .undo:
                return ("UNDO", "arrow.uturn.backward.circle.fill", SwipeDeckTheme.accentUndo, .top)
            }
        }()

        ZStack(alignment: config.alignment) {
            Color.clear
            HStack(spacing: 8) {
                Image(systemName: config.icon)
                    .font(.system(size: 22, weight: .bold))
                Text(config.title)
                    .font(SwipeDeckTypography.roundedTitle(20, weight: .heavy))
            }
            .foregroundStyle(config.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill( Color.black.opacity(0.72) )
                    .overlay(
                        Capsule()
                            .strokeBorder(config.color, lineWidth: 2.5)
                    )
            )
            .padding(24)
            .opacity(opacity)
            .scaleEffect(0.85 + (0.15 * min(1.0, progress)))
        }
        .allowsHitTesting(false)
    }

    private func loadScreenSizeImage() {
        displayImage = nil
        highResZoomImage = nil
        hasRequestedHighResZoom = false
        imageRequestID = AssetPrefetchPipeline.shared.requestCardImage(
            for: asset.id,
            highResolutionForZoom: false
        ) { image, inCloud in
            self.isStreamingFromiCloud = inCloud
            if let image {
                self.displayImage = image
            }
        }
    }
}
