// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "FanController",
    platforms: [.iOS(.v15)],
    products: [.executable(name: "FanController", targets: ["FanController"])],
    dependencies: [.package(url: "https://github.com/kkonteh97/SwiftOBD2", branch: "main")],
    targets: [.executableTarget(name: "FanController", dependencies: ["SwiftOBD2"], path: "Sources")]
)
