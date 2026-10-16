// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDEditDiff",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MDEditDiff", targets: ["MDEditDiffApp"]),
        .library(name: "MDEditDiffCore", targets: ["MDEditDiffCore"]),
    ],
    targets: [
        // File handling with no UI: byte-exact loading and saving.
        .target(name: "MDEditDiffCore"),
        // The macOS app: AppKit document windows with an editor and a WebKit preview.
        .executableTarget(
            name: "MDEditDiffApp",
            dependencies: ["MDEditDiffCore"],
            resources: [.copy("Resources/Preview")]
        ),
        .testTarget(name: "MDEditDiffCoreTests", dependencies: ["MDEditDiffCore"]),
    ]
)
