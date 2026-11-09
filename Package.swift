// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rook",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Rook", targets: ["Rook"]),
    ],
    targets: [
        // Pure logic: geometry, snap math, key parsing, window memory. No AppKit.
        .target(name: "RookCore"),
        // Accessibility API wrappers + display enumeration.
        .target(name: "RookAX", dependencies: ["RookCore"]),
        // Global hotkeys (Carbon) and, later, the mouse event tap.
        .target(name: "RookInput", dependencies: ["RookCore"]),
        // Menu bar item, onboarding, overlays.
        .target(name: "RookUI", dependencies: ["RookCore"]),
        .executableTarget(
            name: "Rook",
            dependencies: ["RookCore", "RookAX", "RookInput", "RookUI"]
        ),
        .testTarget(name: "RookCoreTests", dependencies: ["RookCore"]),
    ]
)
