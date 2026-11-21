// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "BeerCore",
    products: [
        .library(name: "BeerCore", targets: ["BeerCore"])
    ],
    targets: [
        .target(name: "BeerCore"),
        .executableTarget(name: "beerctl", dependencies: ["BeerCore"]),
        .testTarget(name: "BeerCoreTests", dependencies: ["BeerCore"])
    ]
)
