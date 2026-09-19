// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yixi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Yixi", targets: ["Yixi"])
    ],
    targets: [
        .target(
            name: "YixiPolicy",
            path: "Sources/YixiPolicy"
        ),
        .executableTarget(
            name: "Yixi",
            dependencies: ["YixiPolicy"],
            path: "Sources",
            exclude: ["YixiPolicy"]
        ),
        .testTarget(
            name: "YixiTests",
            dependencies: ["YixiPolicy"],
            path: "Tests/YixiTests"
        )
    ]
)
