import SwiftUI
import UIKit
import Photos

/// Native UIKit `UIScrollView` pinch-to-zoom wrapper that anchors two-finger pinch zoom
/// to the exact finger midpoint (focal point) and allows 2-finger panning while zoomed in,
/// snapping smoothly back to `1.0x` on release so single-finger swiping never conflicts.
public struct FocalPinchZoomImageView: UIViewRepresentable {
    public let image: UIImage
    @Binding public var isZooming: Bool
    public let onHighResThresholdReached: () -> Void
    public let onSingleTap: () -> Void

    public init(
        image: UIImage,
        isZooming: Binding<Bool>,
        onHighResThresholdReached: @escaping () -> Void,
        onSingleTap: @escaping () -> Void
    ) {
        self.image = image
        self._isZooming = isZooming
        self.onHighResThresholdReached = onHighResThresholdReached
        self.onSingleTap = onSingleTap
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> ZoomContainerView {
        let view = ZoomContainerView()
        view.coordinator = context.coordinator
        view.configure(with: image)
        return view
    }

    public func updateUIView(_ uiView: ZoomContainerView, context: Context) {
        context.coordinator.parent = self
        uiView.updateImageIfNeeded(image)
    }

    // MARK: - UIKit Container & Gesture Handler

    public final class ZoomContainerView: UIView {
        weak var coordinator: Coordinator?
        let imageView = UIImageView()

        private var pinchGesture: UIPinchGestureRecognizer!
        private var tapGesture: UITapGestureRecognizer!
        private var initialPinchCentroid: CGPoint = .zero
        private var hasRequestedHighRes = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            clipsToBounds = true

            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = true
            addSubview(imageView)

            pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            addGestureRecognizer(pinchGesture)

            tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            tapGesture.numberOfTapsRequired = 1
            addGestureRecognizer(tapGesture)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            if imageView.transform == .identity {
                imageView.frame = bounds
            }
        }

        func configure(with image: UIImage) {
            imageView.image = image
        }

        func updateImageIfNeeded(_ newImage: UIImage) {
            if imageView.image !== newImage {
                imageView.image = newImage
            }
        }

        @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            coordinator?.parent.onSingleTap()
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view else { return }

            switch gesture.state {
            case .began:
                initialPinchCentroid = gesture.location(in: view)
                hasRequestedHighRes = false
                coordinator?.setZooming(true)

            case .changed:
                guard gesture.numberOfTouches >= 2 else { return }

                let currentCentroid = gesture.location(in: view)
                let deltaX = currentCentroid.x - initialPinchCentroid.x
                let deltaY = currentCentroid.y - initialPinchCentroid.y

                let clampedScale = min(5.0, max(1.0, gesture.scale))

                // Anchor the scale around the user's initial pinch focal point
                // plus follow two-finger pan movement seamlessly
                let anchorOffsetX = initialPinchCentroid.x - view.bounds.midX
                let anchorOffsetY = initialPinchCentroid.y - view.bounds.midY

                var transform = CGAffineTransform.identity
                transform = transform.translatedBy(
                    x: deltaX + anchorOffsetX * (1.0 - clampedScale),
                    y: deltaY + anchorOffsetY * (1.0 - clampedScale)
                )
                transform = transform.scaledBy(x: clampedScale, y: clampedScale)
                imageView.transform = transform

                if clampedScale >= 2.0 && !hasRequestedHighRes {
                    hasRequestedHighRes = true
                    coordinator?.parent.onHighResThresholdReached()
                }

            case .ended, .cancelled, .failed:
                // Smoothly snap back to 1.0x identity on release (PRD Section 3.1)
                UIView.animate(
                    withDuration: 0.28,
                    delay: 0,
                    usingSpringWithDamping: 0.78,
                    initialSpringVelocity: 0,
                    options: [.curveEaseOut, .allowUserInteraction]
                ) {
                    self.imageView.transform = .identity
                } completion: { _ in
                    self.coordinator?.setZooming(false)
                }

            default:
                break
            }
        }
    }

    public final class Coordinator: NSObject {
        var parent: FocalPinchZoomImageView

        init(parent: FocalPinchZoomImageView) {
            self.parent = parent
        }

        @MainActor
        func setZooming(_ active: Bool) {
            parent.isZooming = active
        }
    }
}
