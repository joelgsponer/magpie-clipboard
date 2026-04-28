// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Magpie",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Magpie", targets: ["Magpie"]),
    ],
    targets: [
        .executableTarget(
            name: "Magpie",
            path: "Sources/Magpie",
            exclude: ["Resources/Info.plist"]
        ),
    ]
)
