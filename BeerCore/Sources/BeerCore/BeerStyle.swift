import Foundation

/// An sRGB color with components in 0...1. Codable so `beerctl dump-styles`
/// can hand the exact same values to the WebGL preview harness.
public struct RGB: Equatable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// One beer mode: a complete set of liquid-shader parameters.
///
/// The same values drive the iOS `SKShader` uniforms and the browser preview,
/// so a style only needs to be described here once.
public struct BeerStyle: Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    /// Beer color just under the surface (light end of the gradient).
    public let bodyTop: RGB
    /// Beer color deep in the glass.
    public let bodyDeep: RGB
    public let glowColor: RGB
    /// Backlit glow intensity (how much light shines through the beer).
    public let glowStrength: Double
    public let translucency: Double
    public let foamColor: RGB
    /// Foam band thickness in screen units.
    public let foamThick: Double
    /// 0...1 fraction of bubble cells that spawn a bubble.
    public let bubbleDensity: Double
    /// Base bubble radius in screen units.
    public let bubbleSize: Double
    /// Bubble rise speed multiplier.
    public let bubbleSpeed: Double
    /// Rainbow mode hue-cycles the body color over time.
    public let rainbow: Bool

    public init(
        id: String, name: String,
        bodyTop: RGB, bodyDeep: RGB,
        glowColor: RGB, glowStrength: Double, translucency: Double,
        foamColor: RGB, foamThick: Double,
        bubbleDensity: Double, bubbleSize: Double, bubbleSpeed: Double,
        rainbow: Bool
    ) {
        self.id = id
        self.name = name
        self.bodyTop = bodyTop
        self.bodyDeep = bodyDeep
        self.glowColor = glowColor
        self.glowStrength = glowStrength
        self.translucency = translucency
        self.foamColor = foamColor
        self.foamThick = foamThick
        self.bubbleDensity = bubbleDensity
        self.bubbleSize = bubbleSize
        self.bubbleSpeed = bubbleSpeed
        self.rainbow = rainbow
    }

    /// All styles, in menu order.
    public static let all: [BeerStyle] = [.lager, .brownAle, .blackStout, .rainbow]

    public static let lager = BeerStyle(
        id: "lager", name: "Pale Lager",
        bodyTop: RGB(0.973, 0.776, 0.188), bodyDeep: RGB(0.706, 0.463, 0.039),
        glowColor: RGB(1.000, 0.850, 0.400), glowStrength: 0.55, translucency: 0.85,
        foamColor: RGB(0.990, 0.980, 0.940), foamThick: 0.22,
        bubbleDensity: 0.50, bubbleSize: 0.010, bubbleSpeed: 0.55,
        rainbow: false)

    public static let brownAle = BeerStyle(
        id: "brownAle", name: "Brown Ale",
        bodyTop: RGB(0.647, 0.388, 0.122), bodyDeep: RGB(0.290, 0.141, 0.031),
        glowColor: RGB(0.900, 0.620, 0.250), glowStrength: 0.35, translucency: 0.55,
        foamColor: RGB(0.960, 0.920, 0.820), foamThick: 0.19,
        bubbleDensity: 0.30, bubbleSize: 0.008, bubbleSpeed: 0.40,
        rainbow: false)

    public static let blackStout = BeerStyle(
        id: "blackStout", name: "Black Stout",
        bodyTop: RGB(0.180, 0.100, 0.040), bodyDeep: RGB(0.047, 0.020, 0.012),
        glowColor: RGB(0.600, 0.400, 0.180), glowStrength: 0.15, translucency: 0.25,
        foamColor: RGB(0.900, 0.800, 0.620), foamThick: 0.26,
        bubbleDensity: 0.18, bubbleSize: 0.005, bubbleSpeed: 0.25,
        rainbow: false)

    public static let rainbow = BeerStyle(
        id: "rainbow", name: "Rainbow",
        bodyTop: RGB(0.800, 0.200, 0.600), bodyDeep: RGB(0.100, 0.200, 0.800),
        glowColor: RGB(1.000, 1.000, 1.000), glowStrength: 0.40, translucency: 0.70,
        foamColor: RGB(0.980, 0.960, 1.000), foamThick: 0.21,
        bubbleDensity: 0.60, bubbleSize: 0.011, bubbleSpeed: 0.70,
        rainbow: true)
}
