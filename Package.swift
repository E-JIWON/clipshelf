// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipShelf",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClipShelf", path: "Sources/ClipShelf"),
        .testTarget(name: "ClipShelfTests", dependencies: ["ClipShelf"], path: "Tests/ClipShelfTests"),
    ]
)
