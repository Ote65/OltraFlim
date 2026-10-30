// swift-tools-version: 5.9
// Canonical build on this machine: ./script/build_and_run.sh (see README).
import PackageDescription

let package = Package(
    name: "OltraFlim",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OltraFlim", targets: ["OltraFlim"])
    ],
    targets: [
        .executableTarget(
            name: "OltraFlim",
            path: "Sources/OltraFlim"
        )
    ]
)
