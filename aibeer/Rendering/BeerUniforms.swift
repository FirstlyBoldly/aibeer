import Foundation

/// The uniform table mirrored from `aibeer/Shaders/beer.metal`'s
/// `BeerUniforms` struct. Field order matters: Metal packs constant-buffer
/// members by alignment, and Swift's SIMD2/SIMD3 storage matches that
/// layout for this ordering (verified offsets: float3 members are 16-byte
/// aligned in both).
struct BeerUniforms {
    var gravity = SIMD2<Float>(0, -1)
    var tilt = SIMD2<Float>(0, -1)
    var spriteSize = SIMD2<Float>(1, 1)
    var bodyTop = SIMD3<Float>(1, 1, 1)
    var bodyDeep = SIMD3<Float>(1, 1, 1)
    var glowColor = SIMD3<Float>(1, 1, 1)
    var foamColor = SIMD3<Float>(1, 1, 1)
    var fill: Float = 0.5
    var clock: Float = 0
    var wobble: Float = 0
    var glowStrength: Float = 0.5
    var translucency: Float = 0.7
    var foamThick: Float = 0.06
    var bubbleDensity: Float = 0.5
    var bubbleSize: Float = 0.01
    var bubbleSpeed: Float = 0.5
    var rainbow: Float = 0
}
