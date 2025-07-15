// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DashPayiOSWorkspace",
    platforms: [
        .iOS(.v17)
    ],
    dependencies: [
        .package(path: "../rust-dashcore/swift-dash-core-sdk"),
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", from: "0.21.0")
    ],
    targets: []
)