// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tech60",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tech60", targets: ["Tech60App"]),
        .library(name: "Tech60Core", targets: ["Tech60Core"]),
    ],
    targets: [
        // Feeds, Hacker News, storage, "new since you looked", and checked summaries. No UI.
        .target(name: "Tech60Core"),
        // The Mac app: a menu-bar item and a floating news card.
        .executableTarget(name: "Tech60App", dependencies: ["Tech60Core"]),
        .testTarget(name: "Tech60CoreTests", dependencies: ["Tech60Core"]),
    ]
)
