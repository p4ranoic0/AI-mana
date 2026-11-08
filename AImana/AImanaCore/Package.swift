// swift-tools-version: 6.0
import PackageDescription

#if !canImport(Darwin)
let package = Package(
    name: "AImanaCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [.library(name: "AImanaCore", targets: ["AImanaCore"])],
    targets: [.target(name: "AImanaCore", resources: [.process("Resources")]),
              .testTarget(name: "AImanaCoreTests", dependencies: ["AImanaCore"])]
)
#else
let package = Package(
    name: "AImanaCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [.library(name: "AImanaCore", targets: ["AImanaCore"]),
               .library(name: "AImanaSignIn", targets: ["AImanaSignIn"])],
    targets: [.target(name: "AImanaCore", resources: [.process("Resources")]),
              .target(name: "AImanaSignIn", dependencies: ["AImanaCore"]),
              .testTarget(name: "AImanaCoreTests", dependencies: ["AImanaCore", "AImanaSignIn"])]
)
#endif
