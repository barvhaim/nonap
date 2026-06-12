// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoNap",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "NoNap",
            path: "Sources/NoNap"
        )
    ]
)
