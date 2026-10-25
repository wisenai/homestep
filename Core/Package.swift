// swift-tools-version:5.9
import PackageDescription

// Everything HomeStep decides lives here: the step and obstacle detector, what
// gets said and when, places and markers. None of it needs a phone, so
// `swift test` checks it on any Mac.
let package = Package(
    name: "HomeStepCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HomeStepCore", targets: ["HomeStepCore"]),
    ],
    targets: [
        .target(name: "HomeStepCore"),
        .testTarget(
            name: "HomeStepCoreTests",
            dependencies: ["HomeStepCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
