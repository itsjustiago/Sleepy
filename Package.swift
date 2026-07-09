// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sleepy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sleepy",
            path: "Sources/Sleepy"
        )
    ]
)
