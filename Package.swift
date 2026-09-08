// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LyricsWidget",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "LyricsWidget", path: "Sources/LyricsWidget")
    ]
)
