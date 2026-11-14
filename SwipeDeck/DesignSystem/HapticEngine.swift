import UIKit

/// Pre-warmed Haptic Engine implementing PRD Section 6.3 micro-interactions:
/// - Light impact on exact millisecond a dragged card crosses the 120pt threshold
/// - Soft impact on Keep commit
/// - Medium impact on Trash commit
/// - Rigid double-tap haptic on Batch Delete execution
@MainActor
public final class HapticEngine {
    public static let shared = HapticEngine()

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    private var wasAboveThreshold = false

    private init() {
        prepareAll()
    }

    public func prepareAll() {
        lightGenerator.prepare()
        softGenerator.prepare()
        mediumGenerator.prepare()
        rigidGenerator.prepare()
        selectionGenerator.prepare()
    }

    /// Evaluates whether the drag gesture just crossed or uncrossed the commit threshold,
    /// firing `.light` feedback on the exact transition frame.
    public func evaluateDragThreshold(isAboveThreshold: Bool) {
        if isAboveThreshold != wasAboveThreshold {
            wasAboveThreshold = isAboveThreshold
            lightGenerator.impactOccurred(intensity: isAboveThreshold ? 0.9 : 0.5)
            lightGenerator.prepare()
        }
    }

    public func resetThresholdState() {
        wasAboveThreshold = false
    }

    /// Soft impact on Keep (Swipe Right).
    public func fireKeepCommit() {
        wasAboveThreshold = false
        softGenerator.impactOccurred(intensity: 0.85)
        softGenerator.prepare()
    }

    /// Medium impact on Stage for Deletion (Swipe Left).
    public func fireTrashCommit() {
        wasAboveThreshold = false
        mediumGenerator.impactOccurred(intensity: 1.0)
        mediumGenerator.prepare()
    }

    /// Light crisp impact on Defer to Back of Stack (Swipe Up) or Undo (Swipe Down).
    public func fireUtilityCommit() {
        wasAboveThreshold = false
        lightGenerator.impactOccurred(intensity: 0.75)
        lightGenerator.prepare()
    }

    /// Selection tick for rescuing/toggling an item in the Batch Commit grid.
    public func fireSelectionTick() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// Rigid double-tap haptic on Batch Delete execution (PRD Section 6.3).
    public func fireBatchDeleteDoubleTap() {
        rigidGenerator.impactOccurred(intensity: 1.0)
        rigidGenerator.prepare()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(95))
            self.rigidGenerator.impactOccurred(intensity: 1.0)
            self.rigidGenerator.prepare()
        }
    }
}
