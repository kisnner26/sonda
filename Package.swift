// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SondaCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "SondaCore", targets: ["SondaCore"])],
    targets: [
        .target(name: "SondaCore"),
        .testTarget(name: "SondaCoreTests", dependencies: ["SondaCore"]),
    ]
)
