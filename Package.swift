// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SoundController",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "SoundController", path: "Sources/SoundController", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
