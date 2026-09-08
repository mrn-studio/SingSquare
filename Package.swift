// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingSquare",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "SingSquare", path: "Sources/SingSquare")
    ]
)
