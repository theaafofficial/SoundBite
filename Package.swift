// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoundBite",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SoundBite", targets: ["SoundBite"])
    ],
    targets: [
        .executableTarget(
            name: "SoundBite",
            path: "Sources/SoundBite",
            resources: []
        )
    ]
)
