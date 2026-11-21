import BeerCore
import SpriteKit
import UIKit

/// The beer itself: one full-screen sprite running the liquid shader.
///
/// Wires BeerCore (gravity projection, smoothing, wobble, fill state) into
/// shader uniforms every frame, and switches beer styles at runtime.
final class BeerScene: SKScene {
    private(set) var currentStyle: BeerStyle = .lager

    private let liquid = SKSpriteNode(color: .clear, size: CGSize(width: 1, height: 1))
    private var uniforms: [String: SKUniform] = [:]

    private var fillController = FillController()
    private let gravityFilter = GravityFilter()
    private var slosh = SloshModel()
    private var wobble = WobbleModel()

    private var motion: MotionService?
    private let motionLock = NSLock()
    private var latestMotion: (gravity: GravityVector, rate: SIMD3<Double>)?
    private var syntheticGravity: SIMD2<Double>?

    private var clock: Double = 0
    private var lastUpdate: TimeInterval = 0

    // Launch-argument diagnostics (AIBEER_DEBUG=1): color-codes the scene
    // per lifecycle stage and prints live state, so a black screen can be
    // triaged from a single simulator screenshot.
    //   red  = didMove reached, update() never ran
    //   blue = update() running (label shows fill/viewport/shader source)
    private var debugEnabled = false
    private var debugLabel: SKLabelNode?
    private var frameCount = 0
    private var shaderLoadedFromFile = false

    override func didMove(to view: SKView) {
        debugEnabled = ProcessInfo.processInfo.environment["AIBEER_DEBUG"] == "1"
        backgroundColor =
            debugEnabled ? .red : SKColor(red: 0.02, green: 0.024, blue: 0.035, alpha: 1)

        // The scene may be created with size .zero (SwiftUI SpriteView);
        // adopt the view's bounds so the liquid sprite is never 1x1 px.
        if size.width == 0 || size.height == 0 {
            size = view.bounds.size
        }
        liquid.size = size
        liquid.zPosition = 0
        liquid.shader = makeShader()
        applyStyleUniforms()
        addChild(liquid)

        if debugEnabled {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.fontSize = 13
            label.fontColor = .white
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .top
            label.position = CGPoint(x: 16, y: size.height - 12)
            label.zPosition = 10
            label.text = "didMove OK, waiting for update()..."
            addChild(label)
            debugLabel = label
        }

        startMotion(in: view)
        installStyleSwipes(in: view)
    }

    /// Starts live gyro sampling, or the drag fallback when sensors are
    /// unavailable (iOS Simulator, sensorless devices).
    private func startMotion(in view: SKView) {
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
            installPanFallback(in: view)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        liquid.size = size
    }

    /// gl_FragCoord is in pixels while `size` is in points — the shader needs
    /// the pixel viewport, so scale by the view's content scale factor.
    private var pixelSize: SIMD2<Float> {
        let scale = Float(view?.contentScaleFactor ?? 1)
        return SIMD2(Float(size.width) * scale, Float(size.height) * scale)
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60.0 : min(currentTime - lastUpdate, 0.1)
        lastUpdate = currentTime
        // Wrap at 60 s: every shader time multiplier is an integer number of
        // cycles per minute, so the wrap is seamless (and mediump-safe).
        clock = (clock + dt).truncatingRemainder(dividingBy: 60)

        let screenGravity = sampleScreenGravity(dt: dt)
        let smoothed = gravityFilter.update(screenGravity, dt: dt)
        let surface = slosh.update(target: smoothed.direction, dt: dt)
        wobble.decay(dt: dt)
        let amplitude = max(wobble.amplitude, slosh.waveEnergy * 0.06)

        applyFrameUniforms(gravity: smoothed.direction, surface: surface, amplitude: amplitude)

        if debugEnabled {
            frameCount += 1
            backgroundColor = SKColor(red: 0.10, green: 0.15, blue: 0.35, alpha: 1)  // stage 2
            debugLabel?.text =
                "frame \(frameCount)  fill \(String(format: "%.2f", fillController.level))  px \(Int(pixelSize.x))x\(Int(pixelSize.y))  src \(shaderLoadedFromFile ? "file" : "FALLBACK")"
        }
    }

    /// Latest motion sample → screen-space world-down. Falls back to the pan
    /// gesture's synthetic gravity, then to "phone upright".
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

    /// Pushes this frame's simulation state into the shader uniforms.
    private func applyFrameUniforms(
        gravity: SIMD2<Double>, surface: SIMD2<Double>, amplitude: Double
    ) {
        uniforms["u_gravity"]?.vectorFloat2Value = SIMD2(
            Float(gravity.x),
            Float(gravity.y))
        uniforms["u_tilt"]?.vectorFloat2Value = SIMD2(
            Float(surface.x),
            Float(surface.y))
        uniforms["u_fill"]?.floatValue = Float(fillController.level)
        uniforms["u_clock"]?.floatValue = Float(clock)
        uniforms["u_wobble"]?.floatValue = Float(amplitude)
        uniforms["u_spriteSize"]?.vectorFloat2Value = pixelSize
    }

    // MARK: - Controls (called from MainView)

    func select(_ style: BeerStyle) {
        currentStyle = style
        applyStyleUniforms()
    }

    /// Swipe left = next drink, right = previous (wraps around).
    func cycleStyle(forward: Bool) {
        let all = BeerStyle.all
        let idx = all.firstIndex(of: currentStyle) ?? 0
        let next = forward ? (idx + 1) % all.count : (idx + all.count - 1) % all.count
        select(all[next])
    }

    // MARK: - Setup

    private func makeShader() -> SKShader {
        uniforms = Self.makeInitialUniforms(level: Float(fillController.level))
        let shader = SKShader(source: loadShaderSource())
        shader.uniforms = Array(uniforms.values)
        return shader
    }

    private func loadShaderSource() -> String {
        if let url = Bundle.main.url(forResource: "beer-liquid", withExtension: "fsh"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        {
            shaderLoadedFromFile = true
            return text
        }
        shaderLoadedFromFile = false
        return Self.fallbackShader
    }

    /// The full uniform table with neutral defaults; style values overwrite
    /// the color/style entries via `applyStyleUniforms()`.
    private static func makeInitialUniforms(level: Float) -> [String: SKUniform] {
        [
            "u_gravity": SKUniform(name: "u_gravity", vectorFloat2: SIMD2<Float>(0, -1)),
            "u_tilt": SKUniform(name: "u_tilt", vectorFloat2: SIMD2<Float>(0, -1)),
            "u_fill": SKUniform(name: "u_fill", float: level),
            "u_clock": SKUniform(name: "u_clock", float: 0),
            "u_wobble": SKUniform(name: "u_wobble", float: 0),
            "u_spriteSize": SKUniform(name: "u_spriteSize", vectorFloat2: SIMD2<Float>(1, 1)),
            "u_bodyTop": SKUniform(name: "u_bodyTop", vectorFloat3: SIMD3<Float>(1, 1, 1)),
            "u_bodyDeep": SKUniform(name: "u_bodyDeep", vectorFloat3: SIMD3<Float>(1, 1, 1)),
            "u_glowColor": SKUniform(name: "u_glowColor", vectorFloat3: SIMD3<Float>(1, 1, 1)),
            "u_glowStrength": SKUniform(name: "u_glowStrength", float: 0.5),
            "u_translucency": SKUniform(name: "u_translucency", float: 0.7),
            "u_foamColor": SKUniform(name: "u_foamColor", vectorFloat3: SIMD3<Float>(1, 1, 1)),
            "u_foamThick": SKUniform(name: "u_foamThick", float: 0.06),
            "u_bubbleDensity": SKUniform(name: "u_bubbleDensity", float: 0.5),
            "u_bubbleSize": SKUniform(name: "u_bubbleSize", float: 0.01),
            "u_bubbleSpeed": SKUniform(name: "u_bubbleSpeed", float: 0.5),
            "u_rainbow": SKUniform(name: "u_rainbow", float: 0),
        ]
    }

    private func applyStyleUniforms() {
        let s = currentStyle
        uniforms["u_bodyTop"]?.vectorFloat3Value = s.bodyTop.simd3
        uniforms["u_bodyDeep"]?.vectorFloat3Value = s.bodyDeep.simd3
        uniforms["u_glowColor"]?.vectorFloat3Value = s.glowColor.simd3
        uniforms["u_foamColor"]?.vectorFloat3Value = s.foamColor.simd3
        uniforms["u_glowStrength"]?.floatValue = Float(s.glowStrength)
        uniforms["u_translucency"]?.floatValue = Float(s.translucency)
        uniforms["u_foamThick"]?.floatValue = Float(s.foamThick)
        uniforms["u_bubbleDensity"]?.floatValue = Float(s.bubbleDensity)
        uniforms["u_bubbleSize"]?.floatValue = Float(s.bubbleSize)
        uniforms["u_bubbleSpeed"]?.floatValue = Float(s.bubbleSpeed)
        uniforms["u_rainbow"]?.floatValue = s.rainbow ? 1 : 0
    }

    private func installPanFallback(in view: SKView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(pan)
    }

    /// Horizontal swipes change the drink (mirrors the web runtime's flick).
    private func installStyleSwipes(in view: SKView) {
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

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
        // UIKit y-down → screen y-up
        let dir = SIMD2<Double>(Double(translation.x), Double(-translation.y))
        guard dir.length > 8 else { return }
        syntheticGravity = dir.normalized(or: SIMD2(0, -1))
        wobble.add(rotationRate: SIMD3(dir.length * 0.02, 0, 0), dt: 1.0 / 60.0)
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

    /// Shown only if the shader resource is somehow missing from the bundle:
    /// an unmistakable RED screen (diagnostic — black would be ambiguous).
    private static let fallbackShader =
        "void main() { gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0); }"
}

/// Bridges BeerCore's sRGB color model to SpriteKit's float vectors.
extension RGB {
    fileprivate var simd3: SIMD3<Float> {
        SIMD3(Float(r), Float(g), Float(b))
    }
}
