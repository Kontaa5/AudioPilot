// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AudioPilot",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "AudioPilot", path: "Sources/AudioPilot", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
