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
    /// Level change per second while draining (a full glass takes ~5 s).
    public var drainRate: Double = 0.2

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

    /// Pours at `fillRate`, never rising above `ceiling` and never lowering
    /// the level — used by the opening pour and the swipe-up refill (both
    /// stop at the default half-glass level).
    public mutating func pour(dt: Double, ceiling: Double = 1.0) {
        let raised = level + fillRate * max(dt, 0)
        level = max(level, min(max(ceiling, 0), raised))
    }

    /// Drains at up to `drainRate`, scaled by `severity` (0...1) — used for
    /// tilt-drinking: a casual tilt sips, a full drinking tilt gulps.
    public mutating func drain(dt: Double, severity: Double) {
        let s = min(max(severity, 0), 1)
        level = max(0, level - drainRate * (0.4 + 0.6 * s) * max(dt, 0))
    }

    public var isFilled: Bool { level >= 0.999 }
    public var isEmpty: Bool { level <= 0.001 }
}
