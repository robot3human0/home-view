// swift-tools-version:5.9
// HomeView ofis serveri — Mac mini'da ishlaydi. Tashqi kutubxona yo‘q: faqat Apple Network.framework.
import PackageDescription

let package = Package(
    name: "HomeViewServer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../HomeViewProtocol")
    ],
    targets: [
        .executableTarget(
            name: "HomeViewServer",
            dependencies: [.product(name: "HomeViewProtocol", package: "HomeViewProtocol")],
            path: "Sources/HomeViewServer",
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("SystemConfiguration")
            ]
        )
    ]
)
