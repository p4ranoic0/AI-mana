// swift-tools-version: 6.0
import PackageDescription

var targets: [Target] = [
    .target(name: "RelayKit", dependencies: [.product(name: "AImanaCore", package: "AImanaCore")]),
    .executableTarget(name: "usage-relay", dependencies: ["RelayKit", .product(name: "AImanaCore", package: "AImanaCore")]),
    .testTarget(name: "RelayKitTests", dependencies: ["RelayKit", .product(name: "AImanaCore", package: "AImanaCore")]),
]
var products: [Product] = [.library(name: "RelayKit", targets: ["RelayKit"]),
                           .executable(name: "usage-relay", targets: ["usage-relay"])]
#if os(Windows)
targets.append(.executableTarget(
    name: "usage-relay-task",
    dependencies: ["RelayKit", .product(name: "AImanaCore", package: "AImanaCore")],
    linkerSettings: [.unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS",
                                   "-Xlinker", "/ENTRY:mainCRTStartup"])]
))
products.append(.executable(name: "usage-relay-task", targets: ["usage-relay-task"]))
#endif
let package = Package(
    name: "usage-relay",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: [.package(path: "../AImanaCore")],
    targets: targets
)
