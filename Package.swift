// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "FanController",
    platforms: [.iOS(.v15)],
    products: [.executable(name: "FanController", targets: ["FanController"])],
    dependencies: [.package(url: "https://github.com", from: "1.0.0")],
    targets: [.executableTarget(name: "FanController", dependencies: ["SwiftOBD2"], path: "Sources")]
)
