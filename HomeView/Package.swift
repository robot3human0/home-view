// swift-tools-version:5.9
// HomeView — macOS uchun ish stolida to‘rt fasl: qish, bahor, yoz, kuz. Ofis tarmog‘i bilan.
// Barcha animatsiya Core Animation'da (ilova har kadrda hech narsa chizmaydi).
import PackageDescription

let package = Package(
    name: "HomeView",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(path: "../HomeViewProtocol")
    ],
    targets: [
        .executableTarget(
            name: "HomeView",
            dependencies: [.product(name: "HomeViewProtocol", package: "HomeViewProtocol")],
            path: "Sources/HomeView",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Network"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
