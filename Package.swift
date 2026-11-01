// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudSync",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "StudSync", targets: ["StudSyncApp"])],
    dependencies: [.package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.11.3")],
    targets: [
        .target(name: "StudSyncCore", dependencies: ["SwiftSoup"]),
        .executableTarget(name: "StudSyncApp", dependencies: ["StudSyncCore"], resources: [.process("Resources")]),
        .testTarget(name: "StudSyncCoreTests", dependencies: ["StudSyncCore"])
    ]
)
