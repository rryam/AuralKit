// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AuralKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "AuralKit",
            targets: ["AuralKit"]
        )
    ],
    targets: [
        .target(
            name: "AuralKit"
        ),
        .testTarget(
            name: "AuralKitTests",
            dependencies: ["AuralKit"]
        ),
    ]
)
