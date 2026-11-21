import Foundation

/// Gravity expressed in the device's reference frame (values from CoreMotion, in g's).
///
/// Device frame axes: +x = toward the right edge (portrait), +y = toward the top edge,
/// +z = out of the screen.
public struct GravityVector: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// How the UI is currently oriented on the physical screen.
public enum ScreenOrientation: String, CaseIterable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}

/// World-down projected onto the screen plane, in screen coordinates.
///
/// Convention: +x = right, +y = UP (matches `gl_FragCoord` and SpriteKit),
/// so a vertical phone reports "down" as `(0, -1)`.
public struct ScreenGravity: Equatable, Sendable {
    public var dx: Double
    public var dy: Double
    /// |g.z| in g's: 0 = screen vertical, 1 = phone lying flat.
    public var tiltOffScreen: Double

    public init(dx: Double, dy: Double, tiltOffScreen: Double) {
        self.dx = dx
        self.dy = dy
        self.tiltOffScreen = tiltOffScreen
    }

    /// Magnitude of the on-screen projection (1.0 when the screen is vertical).
    public var projectionLength: Double {
        (dx * dx + dy * dy).squareRoot()
    }

    /// False when the projection is degenerate (phone lying flat on a table).
    public var isDirectionValid: Bool {
        projectionLength > 0.05
    }

    /// Unit-length down-direction; safe fallback `(0, -1)` when degenerate.
    public var direction: SIMD2<Double> {
        SIMD2(dx, dy).normalized(or: SIMD2(0, -1), minLength: 0.05)
    }

    public static let down = ScreenGravity(dx: 0, dy: -1, tiltOffScreen: 0)
}

/// Pure math that maps CoreMotion's device-frame gravity into screen space.
public enum GravityProjector {
    /// Projects a device-frame gravity vector for the given UI orientation.
    ///
    /// These mappings are 90° rotations of the portrait result, derived from the
    /// physical relationship between device axes and screen axes per orientation.
    public static func project(_ g: GravityVector, orientation: ScreenOrientation) -> ScreenGravity
    {
        let pair: (Double, Double)
        switch orientation {
        case .portrait:
            pair = (g.x, g.y)
        case .portraitUpsideDown:
            pair = (-g.x, -g.y)
        case .landscapeLeft:
            pair = (-g.y, g.x)
        case .landscapeRight:
            pair = (g.y, -g.x)
        }
        return ScreenGravity(dx: pair.0, dy: pair.1, tiltOffScreen: abs(g.z))
    }
}
