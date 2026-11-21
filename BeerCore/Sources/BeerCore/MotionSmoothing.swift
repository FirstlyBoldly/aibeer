import Foundation

/// Damped-oscillator model of a liquid free surface — the classic
/// single-degree-of-freedom sloshing analog (mass-spring-damper, as used in
/// tank-sloshing literature, tuned for a pint glass).
///
/// The surface angle chases the container's level direction on a spring and,
/// being underdamped, lags behind fast tilts, overshoots, and sloshes back and
/// forth before settling. This lag is the single biggest realism cue for a
/// gyro-driven drink app; a shader alone cannot produce it because the
/// fragment shader is stateless, so the oscillator lives here and feeds the
/// shader a `u_tilt` uniform that may deviate from true gravity.
public struct SloshModel: Sendable {
    /// Current liquid-surface "down" direction (unit length, screen coords, y-up).
    public private(set) var surfaceDirection: SIMD2<Double>
    public private(set) var angularVelocity: Double = 0
    /// Last |angle| between surface and level direction, radians.
    public private(set) var errorAngle: Double = 0

    /// Natural frequency ω₀ in rad/s (≈ 1.4 Hz for a beer glass).
    public var naturalFrequency: Double = 8.8
    /// Damping ratio ζ: 0 = oscillates forever, 1 = no overshoot. Beer ≈ 0.15.
    public var dampingRatio: Double = 0.15
    /// Safety clamp on |deviation| from level, radians.
    public var maxDeviation: Double = 1.2
    /// Safety clamp on |angular velocity|, rad/s.
    public var maxAngularVelocity: Double = 12.0

    public init() {
        surfaceDirection = SIMD2(0, -1)
    }

    /// Advances the oscillator. `target` is the level direction (filtered
    /// gravity); returns the new surface direction.
    @discardableResult
    public mutating func update(target: SIMD2<Double>, dt: Double) -> SIMD2<Double> {
        let step = min(max(dt, 0.0001), 0.05)
        let targetAngle = atan2(target.y, target.x)
        let surfaceAngle = atan2(surfaceDirection.y, surfaceDirection.x)

        var error = Self.wrapPi(targetAngle - surfaceAngle)
        error = min(max(error, -maxDeviation), maxDeviation)
        errorAngle = abs(error)

        let stiffness = naturalFrequency * naturalFrequency
        let damping = 2.0 * dampingRatio * naturalFrequency
        // error = target - surface, so the restoring acceleration is +k·error.
        let angularAccel = stiffness * error - damping * angularVelocity

        angularVelocity += angularAccel * step
        angularVelocity = min(max(angularVelocity, -maxAngularVelocity), maxAngularVelocity)

        let newAngle = surfaceAngle + angularVelocity * step
        surfaceDirection = SIMD2(cos(newAngle), sin(newAngle))
        return surfaceDirection
    }

    /// Instantly aligns the surface with `target` and zeroes velocity.
    public mutating func settle(on target: SIMD2<Double>) {
        surfaceDirection = target.normalized(or: SIMD2(0, -1))
        angularVelocity = 0
        errorAngle = 0
    }

    /// Signed angle (radians) from unit vector `a` to unit vector `b`, in (-π, π].
    public static func signedAngle(from a: SIMD2<Double>, to b: SIMD2<Double>) -> Double {
        wrapPi(atan2(b.y, b.x) - atan2(a.y, a.x))
    }

    /// 0...1 energy measure (surface deviation + surface motion) that scales
    /// the shader's wave amplitude: waves appear when the surface is displaced
    /// from level or moving.
    public var waveEnergy: Double {
        min(1.0, errorAngle / 0.35 + abs(angularVelocity) / naturalFrequency * 0.5)
    }

    /// Wraps an angle to (-π, π].
    static func wrapPi(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * Double.pi)
        if a <= -Double.pi { a += 2 * Double.pi }
        if a > Double.pi { a -= 2 * Double.pi }
        return a
    }
}

/// Exponential low-pass filter over the screen-space gravity direction.
///
/// Smooths raw 60 Hz sensor samples into a stable tilt direction. The filter
/// blends direction vectors (not angles), so there is no wrap-around behavior
/// to worry about, and re-normalizes after each step to keep the result unit-length.
public final class GravityFilter {
    private var direction: SIMD2<Double>
    private var offScreen: Double
    private let tau: Double

    /// - Parameter tau: smoothing time constant in seconds (smaller = snappier).
    public init(tau: Double = 0.12) {
        self.tau = max(tau, 0.001)
        self.direction = SIMD2(0, -1)
        self.offScreen = 0
    }

    /// Feeds one raw sample; returns the smoothed value.
    @discardableResult
    public func update(_ raw: ScreenGravity, dt: Double) -> ScreenGravity {
        let alpha = 1 - exp(-max(dt, 0.001) / tau)
        if raw.isDirectionValid {
            let target = raw.direction
            direction += alpha * (target - direction)
            let len = (direction.x * direction.x + direction.y * direction.y).squareRoot()
            if len > 1e-9 {
                direction /= len
            }
        }
        // When the phone goes flat the direction is meaningless; hold the last one.
        offScreen += alpha * (raw.tiltOffScreen - offScreen)
        return ScreenGravity(dx: direction.x, dy: direction.y, tiltOffScreen: offScreen)
    }

    public var current: ScreenGravity {
        ScreenGravity(dx: direction.x, dy: direction.y, tiltOffScreen: offScreen)
    }
}

/// Accumulates sloshing chop energy from gyroscope rotation rate and decays it
/// over time. Fast twists pump extra surface chop even when the SloshModel's
/// mean surface angle barely moves.
public struct WobbleModel: Sendable {
    public private(set) var energy: Double = 0
    /// Energy gained per (rad/s · s) of rotation.
    public var gain: Double = 1.2
    public var maxEnergy: Double = 1.0
    /// Exponential decay time constant, seconds.
    public var tau: Double = 0.6
    /// Peak wave amplitude (screen units) at full energy.
    public var amplitudeScale: Double = 0.06

    public init() {}

    public mutating func add(rotationRate: SIMD3<Double>, dt: Double) {
        let rate =
            (rotationRate.x * rotationRate.x
            + rotationRate.y * rotationRate.y
            + rotationRate.z * rotationRate.z).squareRoot()
        energy = min(maxEnergy, energy + rate * max(dt, 0) * gain)
    }

    public mutating func decay(dt: Double) {
        energy *= exp(-max(dt, 0) / tau)
    }

    public var amplitude: Double {
        min(energy, maxEnergy) * amplitudeScale
    }
}
