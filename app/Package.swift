// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Nodch",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Nodch", targets: ["Nodch"]),
        .library(name: "NodchCore", targets: ["NodchCore"]),
    ],
    targets: [
        // Nod client (HTTP, SSE, auth), island state and geometry. No AppKit windows here.
        .target(name: "NodchCore"),
        // The app: notch panel, views, hotkey, snapshots.
        .executableTarget(name: "Nodch", dependencies: ["NodchCore"]),
        // Without Xcode there is no XCTest: checks run as `swift run NodchChecks`.
        .executableTarget(name: "NodchChecks", dependencies: ["NodchCore"]),
    ]
)
