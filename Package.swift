// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "KettleStitch", platforms: [.macOS(.v13)], products: [
    .executable(name: "KettleStitch", targets: ["KettleStitch"]),
    .executable(name: "CropCheck", targets: ["CropCheck"])
], targets: [.target(name: "CropCore"), .executableTarget(name: "KettleStitch", dependencies: ["CropCore"]), .executableTarget(name: "CropCheck", dependencies: ["CropCore"]), .testTarget(name: "CropCoreTests", dependencies: ["CropCore"])])
