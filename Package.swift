// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Magpie",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Magpie", targets: ["Magpie"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6"),
    ],
    targets: [
        .executableTarget(
            name: "Magpie",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Magpie",
            exclude: ["Resources/Info.plist"]
        ),
    ]
)
