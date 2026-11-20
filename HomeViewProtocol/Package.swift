// swift-tools-version:5.9
// HomeView — ilova va server o‘rtasidagi umumiy "til" (xabar turlari).
import PackageDescription

let package = Package(
    name: "HomeViewProtocol",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HomeViewProtocol", targets: ["HomeViewProtocol"])
    ],
    targets: [
        .target(name: "HomeViewProtocol", path: "Sources/HomeViewProtocol")
    ]
)
