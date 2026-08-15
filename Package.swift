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
        .executableTarget(
            name: "Yixi",
            path: "Sources"
        )
    ]
)
