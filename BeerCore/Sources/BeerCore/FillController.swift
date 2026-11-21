import Foundation

/// Fill level state machine: eases `level` toward `target` over time.
///
/// Draining is intentionally faster than filling — beer glugs out faster
/// than a tap pours it in.
public struct FillController: Sendable {
    public private(set) var level: Double
    public var target: Double
    /// Level change per second while filling (~4.5 s for a full pour).
    public var fillRate: Double = 0.22
    /// Level change per second while draining.
    public var drainRate: Double = 0.55

    public init(level: Double = 0.5) {
        let clamped = min(max(level, 0), 1)
        self.level = clamped
        self.target = clamped
    }

    public mutating func advance(dt: Double) {
        let step = max(dt, 0)
        let goal = min(max(target, 0), 1)
        if goal > level {
            level = min(goal, level + fillRate * step)
        } else if goal < level {
            level = max(goal, level - drainRate * step)
        }
    }

    public var isFilled: Bool { level >= 0.999 }
    public var isEmpty: Bool { level <= 0.001 }
}
