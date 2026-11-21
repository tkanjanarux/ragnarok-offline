// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ViewportCheck", platforms: [.iOS(.v18)], products: [.library(name: "ViewportCheck", targets: ["ViewportCheck"])], targets: [.target(name: "ViewportCheck", path: "Sources"), .testTarget(name: "ViewportCheckTests", dependencies: ["ViewportCheck"], path: "Tests")])
