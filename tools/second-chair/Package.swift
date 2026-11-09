// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SecondChair",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "SecondChair", targets: ["SecondChairApp"]),
        .library(name: "SecondChairCore", targets: ["SecondChairCore"]),
    ],
    targets: [
        // Everything that decides what you see: chunking, retrieval, labels, the grounding check,
        // question detection, the consent gate, session review and the evaluation gate. No UI, no audio.
        .target(name: "SecondChairCore"),
        // The Mac app: the private overlay, your document library, the local models, listening and sessions.
        .executableTarget(
            name: "SecondChairApp",
            dependencies: ["SecondChairCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("PDFKit"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("FoundationModels"),
            ]
        ),
        .testTarget(name: "SecondChairCoreTests", dependencies: ["SecondChairCore"]),
    ]
)
