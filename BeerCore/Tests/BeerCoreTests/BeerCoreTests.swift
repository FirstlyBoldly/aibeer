import XCTest
@testable import BeerCore

final class BeerCoreTests: XCTestCase {

    private func assertDirection(_ d: SIMD2<Double>, _ x: Double, _ y: Double,
                                 accuracy: Double = 1e-9,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(d.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(d.y, y, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - GravityProjector

    func testPortraitUprightWorldDownIsScreenDown() {
        let g = GravityProjector.project(GravityVector(x: 0, y: -1, z: 0), orientation: .portrait)
        assertDirection(g.direction, 0, -1)
        XCTAssertEqual(g.tiltOffScreen, 0, accuracy: 1e-9)
    }

    func testPortraitRightEdgeDownPoolsToScreenRight() {
        let g = GravityProjector.project(GravityVector(x: 0.7, y: -0.7, z: 0), orientation: .portrait)
        let d = g.direction
        XCTAssertGreaterThan(d.x, 0.6)
        XCTAssertLessThan(d.y, -0.6)
    }

    func testLandscapeLeftUprightWorldDownIsScreenRight() {
        // landscapeLeft = home button on the right; device bottom edge faces screen-right.
        let g = GravityProjector.project(GravityVector(x: 0, y: -1, z: 0), orientation: .landscapeLeft)
        XCTAssertEqual(g.direction.x, 1, accuracy: 1e-9)
        XCTAssertEqual(g.direction.y, 0, accuracy: 1e-9)
    }

    func testLandscapeRightUprightWorldDownIsScreenLeft() {
        let g = GravityProjector.project(GravityVector(x: 0, y: -1, z: 0), orientation: .landscapeRight)
        XCTAssertEqual(g.direction.x, -1, accuracy: 1e-9)
        XCTAssertEqual(g.direction.y, 0, accuracy: 1e-9)
    }

    func testUpsideDownPortraitMapsWorldDownToScreenDown() {
        // Device upside down: gravity points toward device top edge (+y).
        let g = GravityProjector.project(GravityVector(x: 0, y: 1, z: 0), orientation: .portraitUpsideDown)
        assertDirection(g.direction, 0, -1)
    }

    func testFlatOnTableIsDegenerateWithSafeFallback() {
        let g = GravityProjector.project(GravityVector(x: 0, y: 0, z: -1), orientation: .portrait)
        XCTAssertFalse(g.isDirectionValid)
        assertDirection(g.direction, 0, -1)
        XCTAssertEqual(g.tiltOffScreen, 1, accuracy: 1e-9)
    }

    func testTiltOffScreenTracksAbsZ() {
        let g = GravityProjector.project(GravityVector(x: 0.6, y: -0.8, z: 0.5), orientation: .portrait)
        XCTAssertEqual(g.tiltOffScreen, 0.5, accuracy: 1e-9)
    }

    func testProjectionLengthIsOneWhenVertical() {
        let g = GravityProjector.project(GravityVector(x: 0.6, y: -0.8, z: 0), orientation: .portrait)
        XCTAssertEqual(g.projectionLength, 1, accuracy: 1e-9)
    }

    // MARK: - GravityFilter

    func testFilterConvergesToConstantInput() {
        let filter = GravityFilter()
        var out = filter.current
        for _ in 0..<240 {
            out = filter.update(ScreenGravity(dx: 1, dy: 0, tiltOffScreen: 0), dt: 1.0 / 60.0)
        }
        XCTAssertEqual(out.direction.x, 1, accuracy: 0.01)
        XCTAssertEqual(out.direction.y, 0, accuracy: 0.01)
    }

    func testFilterResponseIsGradualNotTeleporting() {
        let filter = GravityFilter()
        _ = filter.update(ScreenGravity.down, dt: 1.0 / 60.0)
        let out = filter.update(ScreenGravity(dx: 1, dy: 0, tiltOffScreen: 0), dt: 1.0 / 60.0)
        // Angle swept from "down" toward "right" after a single 60 Hz step must be
        // a small fraction of the full 90° turn (low-pass behavior).
        let angle = atan2(out.direction.x, -out.direction.y)
        XCTAssertGreaterThan(angle, 0.01)
        XCTAssertLessThan(angle, .pi / 4)
    }

    func testFilterHoldsDirectionWhenPhoneGoesFlat() {
        let filter = GravityFilter()
        _ = filter.update(ScreenGravity.down, dt: 1.0 / 60.0)
        var out = ScreenGravity.down
        for _ in 0..<60 {
            out = filter.update(ScreenGravity(dx: 0, dy: 0, tiltOffScreen: 1), dt: 1.0 / 60.0)
        }
        assertDirection(out.direction, 0, -1)
        XCTAssertEqual(out.tiltOffScreen, 1, accuracy: 0.01)
    }

    // MARK: - VectorMath

    func testVectorLength() {
        let v = SIMD2(3.0, 4.0)
        XCTAssertEqual(v.length, 5, accuracy: 1e-12)
    }

    func testNormalizedReturnsUnitVector() {
        let v = SIMD2(3.0, 4.0)
        let n = v.normalized(or: SIMD2(0, -1))
        XCTAssertEqual(n.x, 0.6, accuracy: 1e-12)
        XCTAssertEqual(n.y, 0.8, accuracy: 1e-12)
        XCTAssertEqual(n.length, 1, accuracy: 1e-12)
    }

    func testNormalizedFallsBackOnDegenerateVector() {
        let zero = SIMD2(0.0, 0.0)
        let fallback = SIMD2(0.0, -1.0)
        let n = zero.normalized(or: fallback)
        XCTAssertEqual(n, fallback)
    }

    func testNormalizedRespectsMinLength() {
        let tiny = SIMD2(0.04, 0.0)   // length 0.04 < 0.05
        let fallback = SIMD2(1.0, 0.0)
        XCTAssertEqual(tiny.normalized(or: fallback, minLength: 0.05), fallback)
        XCTAssertEqual(tiny.normalized(or: fallback, minLength: 0.03).x, 1, accuracy: 1e-12)
    }

    // MARK: - WobbleModel

    func testWobblePumpsWithRotationAndDecays() {
        var w = WobbleModel()
        w.add(rotationRate: SIMD3(3, 0, 0), dt: 0.2)
        XCTAssertGreaterThan(w.energy, 0.5)
        let before = w.energy
        w.decay(dt: 1.0)
        XCTAssertLessThan(w.energy, before * 0.3) // exp(-1/0.6) ≈ 0.19
    }

    func testWobbleEnergyAndAmplitudeClamp() {
        var w = WobbleModel()
        for _ in 0..<100 {
            w.add(rotationRate: SIMD3(10, 10, 10), dt: 0.1)
        }
        XCTAssertLessThanOrEqual(w.energy, w.maxEnergy + 1e-9)
        XCTAssertLessThanOrEqual(w.amplitude, w.amplitudeScale + 1e-9)
    }

    // MARK: - SloshModel

    func testSloshSettlesAtLevelDirection() {
        var s = SloshModel()
        s.settle(on: SIMD2(0, -1))
        var out = SIMD2(0.0, -1.0)
        for _ in 0..<600 {
            out = s.update(target: SIMD2(1, 0), dt: 1.0 / 60.0)
        }
        // After 10 s the surface must sit on the level direction.
        let level = SIMD2(1.0, 0.0)
        XCTAssertEqual(SloshModel.signedAngle(from: out, to: level), 0, accuracy: 0.01)
        XCTAssertLessThan(s.waveEnergy, 0.05)
    }

    func testSloshLagsBehindSuddenTilt() {
        var s = SloshModel()
        s.settle(on: SIMD2(0, -1))
        // One frame after a 90° container tilt the surface must NOT have arrived.
        let out = s.update(target: SIMD2(1, 0), dt: 1.0 / 60.0)
        let arrived = abs(out.x - 1) < 0.05 && abs(out.y) < 0.05
        XCTAssertFalse(arrived)
        XCTAssertGreaterThan(s.waveEnergy, 0.2)
    }

    func testSloshOvershootsLikeRealLiquid() {
        var s = SloshModel()
        s.settle(on: SIMD2(0, -1))
        // Underdamped surface crosses the level direction at least once.
        var crossed = false
        var previousError = Double.pi
        let level = SIMD2(1.0, 0.0)
        for _ in 0..<300 {
            let out = s.update(target: level, dt: 1.0 / 60.0)
            let err = SloshModel.signedAngle(from: out, to: level)
            if previousError < 0 && err > 0 {
                crossed = true
            }
            previousError = err
        }
        XCTAssertTrue(crossed, "underdamped slosh should overshoot the level direction")
    }

    func testSloshIsStableUnderLongRun() {
        var s = SloshModel()
        s.settle(on: SIMD2(0, -1))
        // Simulated wobbly hand: alternating targets, no NaN, unit direction.
        for i in 0..<10000 {
            let t = (i / 90) % 2 == 0 ? SIMD2(0.7, -0.7) : SIMD2(-0.6, -0.8)
            let out = s.update(target: t, dt: 1.0 / 60.0)
            let len = (out.x * out.x + out.y * out.y).squareRoot()
            XCTAssertEqual(len, 1, accuracy: 1e-6)
            XCTAssertFalse(out.x.isNaN)
            XCTAssertFalse(out.y.isNaN)
        }
    }

    func testSloshSettleIsInstant() {
        var s = SloshModel()
        s.update(target: SIMD2(1, 0), dt: 1.0 / 60.0)
        s.settle(on: SIMD2(0.6, -0.8))
        XCTAssertEqual(s.surfaceDirection.x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(s.surfaceDirection.y, -0.8, accuracy: 1e-9)
        XCTAssertEqual(s.angularVelocity, 0, accuracy: 1e-12)
        XCTAssertEqual(s.errorAngle, 0, accuracy: 1e-12)
    }

    func testWrapPiHandlesAllQuadrants() {
        XCTAssertEqual(SloshModel.wrapPi(0), 0, accuracy: 1e-12)
        XCTAssertEqual(SloshModel.wrapPi(4 * .pi), 0, accuracy: 1e-9)
        XCTAssertEqual(SloshModel.wrapPi(-4 * .pi), 0, accuracy: 1e-9)
        XCTAssertEqual(SloshModel.wrapPi(2 * .pi + 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SloshModel.wrapPi(3 * .pi), .pi, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(SloshModel.wrapPi(.pi), .pi)
        XCTAssertGreaterThan(SloshModel.wrapPi(-.pi), -.pi)
    }

    // MARK: - FillController

    func testFillAdvancesTowardTargetAndClamps() {
        var f = FillController(level: 0.2)
        f.target = 1
        for _ in 0..<600 {
            f.advance(dt: 1.0 / 60.0)
        }
        XCTAssertEqual(f.level, 1, accuracy: 1e-9)
        XCTAssertTrue(f.isFilled)
    }

    func testDrainReachesEmpty() {
        var f = FillController(level: 0.8)
        f.target = 0
        for _ in 0..<600 {
            f.advance(dt: 1.0 / 60.0)
        }
        XCTAssertEqual(f.level, 0, accuracy: 1e-9)
        XCTAssertTrue(f.isEmpty)
    }

    func testDrainSlowerThanFill() {
        // The drain is deliberately unhurried: a full glass takes ~5 s.
        XCTAssertLessThan(FillController().drainRate, FillController().fillRate)
        var fill = FillController(level: 0)
        fill.target = 1
        fill.advance(dt: 1)
        XCTAssertEqual(fill.level, fill.fillRate, accuracy: 1e-9)
        var drain = FillController(level: 1)
        drain.target = 0
        drain.advance(dt: 1)
        XCTAssertEqual(drain.level, 1 - drain.drainRate, accuracy: 1e-9)
    }

    func testPourRespectsCeilingAndNeverLowers() {
        var f = FillController(level: 0)
        f.pour(dt: 10, ceiling: 0.5)               // long pour stops at ceiling
        XCTAssertEqual(f.level, 0.5, accuracy: 1e-9)
        f.pour(dt: 10, ceiling: 0.5)
        XCTAssertEqual(f.level, 0.5, accuracy: 1e-9)
        var high = FillController(level: 0.8)
        high.pour(dt: 1, ceiling: 0.5)             // pour never lowers the level
        XCTAssertEqual(high.level, 0.8, accuracy: 1e-9)
    }

    func testOutOfRangeTargetIsClamped() {
        var f = FillController(level: 0.5)
        f.target = 2
        for _ in 0..<600 {
            f.advance(dt: 1)
        }
        XCTAssertLessThanOrEqual(f.level, 1)
        f.target = -3
        for _ in 0..<600 {
            f.advance(dt: 1)
        }
        XCTAssertGreaterThanOrEqual(f.level, 0)
    }

    func testPourAndDrainFlowMethods() {
        var f = FillController(level: 0.5)
        f.pour(dt: 1.0)
        XCTAssertEqual(f.level, 0.5 + f.fillRate, accuracy: 1e-9)
        f.pour(dt: 60.0)   // long pour clamps at full
        XCTAssertEqual(f.level, 1, accuracy: 1e-9)

        f.drain(dt: 1.0, severity: 1.0)
        XCTAssertEqual(f.level, 1 - f.drainRate, accuracy: 1e-9)
        let afterHalfSeverity = f.level
        f.drain(dt: 1.0, severity: 0.5)
        XCTAssertEqual(f.level, afterHalfSeverity - f.drainRate * 0.7, accuracy: 1e-9)
        f.drain(dt: 60.0, severity: 1.0)   // long drain clamps at empty
        XCTAssertEqual(f.level, 0, accuracy: 1e-9)
        XCTAssertTrue(f.isEmpty)
    }

    func testPourAndDrainRespectBounds() {
        var f = FillController(level: 1)
        f.drain(dt: 0.5, severity: 0)   // zero severity still drains at base rate
        XCTAssertLessThan(f.level, 1)
        f.pour(dt: 0.001)
        XCTAssertLessThanOrEqual(f.level, 1)
    }

    func testPourAndDrainRespectBounds2() {
        var f = FillController(level: 0)
        f.drain(dt: 1, severity: 1)
        XCTAssertEqual(f.level, 0, accuracy: 1e-9)  // never below empty
        f.pour(dt: 10)                              // long pour clamps at full
        XCTAssertEqual(f.level, 1, accuracy: 1e-9)  // never above full
    }

    // MARK: - BeerStyle

    func testFourStylesCompleteAndDistinct() {
        XCTAssertEqual(BeerStyle.all.count, 4)
        XCTAssertEqual(Set(BeerStyle.all.map(\.id)).count, 4)
        XCTAssertEqual(Set(BeerStyle.all.map { "\($0.bodyTop)-\($0.bodyDeep)" }).count, 4)
        for style in BeerStyle.all {
            XCTAssertGreaterThan(style.glowStrength, 0)
            XCTAssertGreaterThan(style.foamThick, 0)
            XCTAssertGreaterThan(style.bubbleDensity, 0)
            XCTAssertGreaterThan(style.bubbleSpeed, 0)
        }
    }

    func testOnlyRainbowIsFlaggedRainbow() {
        XCTAssertEqual(BeerStyle.all.filter(\.rainbow).map(\.id), ["rainbow"])
    }

    func testStylesRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(BeerStyle.all)
        XCTAssertGreaterThan(data.count, 200)
        let decoded = try JSONDecoder().decode([BeerStyle].self, from: data)
        XCTAssertEqual(decoded, BeerStyle.all)
    }
}
