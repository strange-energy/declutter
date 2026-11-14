import Foundation
import SwiftUI

/// Non-intrusive, encouraging companion mascot that grows and morphs based on **total app usage**
/// (every photo/video reviewed — whether Kept, Staged for Trash, or Completed in a session — grants XP,
/// so users are rewarded for curating and organizing their library, not forced to delete memories).
public struct AvatarCompanionProgress: Equatable, Sendable {
    public enum Stage: Int, CaseIterable, Sendable {
        case sprout = 1     // Level 1: Tiny Pixel Sprout (0 – 24 XP)
        case pebble = 2     // Level 2: Curious Lens Blob (25 – 99 XP)
        case buddy = 3      // Level 3: Bouncy Shutter Sprite (100 – 299 XP)
        case guardian = 4   // Level 4: Radiant Memory Guardian (300 – 799 XP)
        case cosmic = 5     // Level 5: Cosmic Archive Titan (800+ XP)

        public var title: String {
            switch self {
            case .sprout: return "Tiny Sprout"
            case .pebble: return "Curious Blob"
            case .buddy: return "Shutter Sprite"
            case .guardian: return "Memory Guardian"
            case .cosmic: return "Cosmic Titan"
            }
        }

        public var encouragementLine: String {
            switch self {
            case .sprout:
                return "Just hatched! Every swipe helps me grow."
            case .pebble:
                return "Getting bigger! You're building a great habit."
            case .buddy:
                return "Look at me bounce! Your camera roll is breathing."
            case .guardian:
                return "Glowing strong! You're a true photo curator."
            case .cosmic:
                return "Maximum evolution! Master of the camera roll."
            }
        }

        /// Relative visual scale of the avatar from small (0.68x) to huge (1.28x).
        public var visualScale: CGFloat {
            switch self {
            case .sprout: return 0.68
            case .pebble: return 0.82
            case .buddy: return 0.96
            case .guardian: return 1.12
            case .cosmic: return 1.28
            }
        }

        public var primaryColor: Color {
            switch self {
            case .sprout: return Color(red: 0.40, green: 0.88, blue: 0.55)
            case .pebble: return Color(red: 0.25, green: 0.78, blue: 0.98)
            case .buddy: return Color(red: 0.62, green: 0.52, blue: 1.00)
            case .guardian: return Color(red: 1.00, green: 0.68, blue: 0.22)
            case .cosmic: return Color(red: 1.00, green: 0.38, blue: 0.72)
            }
        }

        public var secondaryColor: Color {
            switch self {
            case .sprout: return Color(red: 0.18, green: 0.65, blue: 0.42)
            case .pebble: return Color(red: 0.12, green: 0.48, blue: 0.92)
            case .buddy: return Color(red: 0.35, green: 0.24, blue: 0.88)
            case .guardian: return Color(red: 0.95, green: 0.36, blue: 0.20)
            case .cosmic: return Color(red: 0.52, green: 0.22, blue: 0.98)
            }
        }

        public var xpFloor: Int {
            switch self {
            case .sprout: return 0
            case .pebble: return 25
            case .buddy: return 100
            case .guardian: return 300
            case .cosmic: return 800
            }
        }

        public var nextStageXP: Int? {
            switch self {
            case .sprout: return 25
            case .pebble: return 100
            case .buddy: return 300
            case .guardian: return 800
            case .cosmic: return nil
            }
        }
    }

    public let totalXP: Int
    public let totalSwipes: Int
    public let sessionsCompleted: Int

    /// Computes total usage XP from app activity (1 XP per photo triaged + 15 bonus XP per session completed).
    public init(totalSwipes: Int, sessionsCompleted: Int) {
        self.totalSwipes = max(0, totalSwipes)
        self.sessionsCompleted = max(0, sessionsCompleted)
        self.totalXP = self.totalSwipes + (self.sessionsCompleted * 15)
    }

    public var stage: Stage {
        if totalXP >= Stage.cosmic.xpFloor { return .cosmic }
        if totalXP >= Stage.guardian.xpFloor { return .guardian }
        if totalXP >= Stage.buddy.xpFloor { return .buddy }
        if totalXP >= Stage.pebble.xpFloor { return .pebble }
        return .sprout
    }

    public var progressToNextStage: Double {
        guard let nextXP = stage.nextStageXP else { return 1.0 }
        let span = max(1, nextXP - stage.xpFloor)
        let earnedInStage = max(0, totalXP - stage.xpFloor)
        return min(1.0, Double(earnedInStage) / Double(span))
    }

    public var xpRemainingToNextStage: Int? {
        guard let nextXP = stage.nextStageXP else { return nil }
        return max(0, nextXP - totalXP)
    }
}
