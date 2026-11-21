import BeerCore
import Foundation
import UIKit

/// Owns the simulation (BeerCore) and turns it into shader uniforms each
/// frame. Also hosts the gesture handlers: drag = tilt (when no live gyro),
/// horizontal swipe = change drink.
final class BeerEngine {
    private(set) var currentStyle: BeerStyle = .lager
    private(set) var uniforms = BeerUniforms()

    private var fillController = FillController()
    private let gravityFilter = GravityFilter()
    private var slosh = SloshModel()
    private var wobble = WobbleModel()

    private var motion: MotionService?
    private let motionLock = NSLock()
    private var latestMotion: (gravity: GravityVector, rate: SIMD3<Double>)?
    private var syntheticGravity: SIMD2<Double>?

    private var clock: Double = 0

    /// Starts motion sampling (or installs the drag fallback) and gestures.
    func attach(to view: UIView) {
        let service = MotionService()
        service.onSample = { [weak self] gravity, rate in
            guard let self else { return }
            self.motionLock.lock()
            defer { self.motionLock.unlock() }
            self.latestMotion = (gravity, rate)
        }
        service.start()
        motion = service

        if !service.isAvailable {
            // iOS Simulator / sensorless device: drag on screen fakes the tilt.
            installPanFallback(in: view)
        }
        installStyleSwipes(in: view)
    }

    /// Advances the simulation by `dt` seconds and refreshes `uniforms`.
    func advance(dt: Double) {
        // Wrap at 60 s: every shader time multiplier is an integer number of
        // cycles per minute, so the wrap is seamless (and mediump-safe).
        clock = (clock + dt).truncatingRemainder(dividingBy: 60)

        let screenGravity = sampleScreenGravity(dt: dt)
        let smoothed = gravityFilter.update(screenGravity, dt: dt)
        let surface = slosh.update(target: smoothed.direction, dt: dt)
        wobble.decay(dt: dt)
        let amplitude = max(wobble.amplitude, slosh.waveEnergy * 0.06)

        uniforms.gravity = SIMD2(Float(smoothed.direction.x), Float(smoothed.direction.y))
        uniforms.tilt = SIMD2(Float(surface.x), Float(surface.y))
        uniforms.fill = Float(fillController.level)
        uniforms.clock = Float(clock)
        uniforms.wobble = Float(amplitude)
        applyStyleUniforms()
    }

    // MARK: - Controls

    func select(_ style: BeerStyle) {
        currentStyle = style
    }

    /// Swipe left = next drink, right = previous (wraps around).
    func cycleStyle(forward: Bool) {
        let all = BeerStyle.all
        let idx = all.firstIndex(of: currentStyle) ?? 0
        let next = forward ? (idx + 1) % all.count : (idx + all.count - 1) % all.count
        select(all[next])
    }

    // MARK: - Motion

    private func sampleScreenGravity(dt: Double) -> ScreenGravity {
        motionLock.lock()
        let sample = latestMotion
        motionLock.unlock()

        if let sample {
            wobble.add(rotationRate: sample.rate, dt: dt)
            return GravityProjector.project(sample.gravity, orientation: Self.orientation)
        }
        if let synthetic = syntheticGravity {
            return ScreenGravity(dx: synthetic.x, dy: synthetic.y, tiltOffScreen: 0)
        }
        return ScreenGravity.down
    }

    /// Maps the current device orientation to BeerCore's screen orientation.
    static var orientation: ScreenOrientation {
        switch UIDevice.current.orientation {
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }

    // MARK: - Gestures

    private func installPanFallback(in view: UIView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
        // UIKit y-down → screen y-up
        let dir = SIMD2<Double>(Double(translation.x), Double(-translation.y))
        guard dir.length > 8 else { return }
        syntheticGravity = dir.normalized(or: SIMD2(0, -1))
        wobble.add(rotationRate: SIMD3(dir.length * 0.02, 0, 0), dt: 1.0 / 60.0)
    }

    /// Horizontal swipes change the drink (mirrors the web runtime's flick).
    private func installStyleSwipes(in view: UIView) {
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(
                target: self, action: #selector(handleStyleSwipe(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)
        }
    }

    @objc private func handleStyleSwipe(_ gesture: UISwipeGestureRecognizer) {
        cycleStyle(forward: gesture.direction == .left)
    }

    // MARK: - Uniforms

    private func applyStyleUniforms() {
        let s = currentStyle
        uniforms.bodyTop = s.bodyTop.simd3
        uniforms.bodyDeep = s.bodyDeep.simd3
        uniforms.glowColor = s.glowColor.simd3
        uniforms.foamColor = s.foamColor.simd3
        uniforms.glowStrength = Float(s.glowStrength)
        uniforms.translucency = Float(s.translucency)
        uniforms.foamThick = Float(s.foamThick)
        uniforms.bubbleDensity = Float(s.bubbleDensity)
        uniforms.bubbleSize = Float(s.bubbleSize)
        uniforms.bubbleSpeed = Float(s.bubbleSpeed)
        uniforms.rainbow = s.rainbow ? 1 : 0
    }
}

/// Bridges BeerCore's sRGB color model to Metal float vectors.
extension RGB {
    fileprivate var simd3: SIMD3<Float> {
        SIMD3(Float(r), Float(g), Float(b))
    }
}
