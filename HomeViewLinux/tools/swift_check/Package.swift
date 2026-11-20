// swift-tools-version:5.9
// Проверка совместимости Linux-клиента с настоящим Swift-протоколом HomeView.
// Запускается из run.sh внутри Docker-контейнера swift:6.0-noble.
import PackageDescription

let package = Package(
    name: "Check",
    dependencies: [.package(path: "/HomeViewProtocol")],
    targets: [
        .executableTarget(name: "Check",
                          dependencies: [.product(name: "HomeViewProtocol", package: "HomeViewProtocol")])
    ]
)
