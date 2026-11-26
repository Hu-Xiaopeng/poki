// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BackgroundMatrix",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "BackgroundMatrix", targets: ["BackgroundMatrix"])],
    targets: [
        .target(name: "BackgroundMatrix"),
        .testTarget(name: "BackgroundMatrixTests", dependencies: ["BackgroundMatrix"])
    ]
)
