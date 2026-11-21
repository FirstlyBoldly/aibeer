import BeerCore
import CoreMotion
import Foundation

/// Publishes CoreMotion device-motion samples (gravity + rotation rate) and
/// reports whether real sensors are available. When they are not (iOS
/// Simulator, sensorless devices), callers fall back to the pan-gesture
/// simulator built into `BeerScene`.
final class MotionService {
    private let manager = CMMotionManager()

    /// Called on a background queue for each device-motion sample.
    /// Arguments: gravity in device frame (g's), rotation rate (rad/s).
    var onSample: ((GravityVector, SIMD3<Double>) -> Void)?

    private(set) var isAvailable = false

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        isAvailable = true
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gravity = GravityVector(
                x: motion.gravity.x,
                y: motion.gravity.y,
                z: motion.gravity.z)
            let rate = SIMD3(
                motion.rotationRate.x,
                motion.rotationRate.y,
                motion.rotationRate.z)
            self.onSample?(gravity, rate)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isAvailable = false
    }
}
