// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "usage-relay",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RelayKit", targets: ["RelayKit"]),
               .executable(name: "usage-relay", targets: ["usage-relay"])],
    dependencies: [.package(path: "../AImanaCore")],
    targets: [
        .target(name: "RelayKit", dependencies: [.product(name: "AImanaCore", package: "AImanaCore")]),
        .executableTarget(name: "usage-relay", dependencies: ["RelayKit", .product(name: "AImanaCore", package: "AImanaCore")]),
        .testTarget(name: "RelayKitTests", dependencies: ["RelayKit", .product(name: "AImanaCore", package: "AImanaCore")]),
    ]
)
