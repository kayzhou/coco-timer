// swift-tools-version: 6.0
import PackageDescription

// 菜单栏应用依赖 AppKit，只在 macOS 上声明可执行目标。
// YixiPolicy 与单测只依赖 Foundation，Linux 上的 Cloud Agent 可以跑 `swift test`。
var products: [Product] = [
    .library(name: "YixiPolicy", targets: ["YixiPolicy"])
]

var targets: [Target] = [
    .target(
        name: "YixiPolicy",
        path: "Sources/YixiPolicy"
    ),
    .testTarget(
        name: "YixiTests",
        dependencies: ["YixiPolicy"],
        path: "Tests/YixiTests"
    )
]

#if os(macOS)
products.append(
    .executable(name: "Yixi", targets: ["Yixi"])
)
targets.append(
    .executableTarget(
        name: "Yixi",
        dependencies: ["YixiPolicy"],
        path: "Sources",
        exclude: ["YixiPolicy"]
    )
)
#endif

let package = Package(
    name: "Yixi",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    targets: targets
)
