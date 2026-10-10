// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PageCrop", platforms: [.macOS(.v13)], products: [
    .executable(name: "PageCrop", targets: ["PageCrop"]),
    .executable(name: "CropCheck", targets: ["CropCheck"])
], targets: [.target(name: "CropCore"), .executableTarget(name: "PageCrop", dependencies: ["CropCore"]), .executableTarget(name: "CropCheck", dependencies: ["CropCore"]), .testTarget(name: "CropCoreTests", dependencies: ["CropCore"])])
