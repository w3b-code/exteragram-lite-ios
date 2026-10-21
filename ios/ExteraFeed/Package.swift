// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "ExteraFeed", platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "ExteraFeed", targets: ["ExteraFeed"])],
    targets: [.target(name: "ExteraFeed"), .testTarget(name: "ExteraFeedTests", dependencies: ["ExteraFeed"])])
