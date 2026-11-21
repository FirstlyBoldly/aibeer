import Foundation

/// Small 2D vector helpers shared by the gravity pipeline.
///
/// The "safe normalize with explicit degenerate fallback" pattern appears in
/// several places (screen projection, slosh settle, pan fallback) — it lives
/// here so the invariants stay in one place.
extension SIMD2 where Scalar == Double {
    /// Euclidean length.
    public var length: Double {
        (x * x + y * y).squareRoot()
    }

    /// Unit-length copy, or `fallback` when the vector is shorter than
    /// `minLength` (degenerate — e.g. the phone lying flat on a table).
    public func normalized(or fallback: SIMD2<Double>, minLength: Double = 1e-9) -> SIMD2<Double> {
        let len = length
        guard len >= minLength else { return fallback }
        return self / len
    }
}
