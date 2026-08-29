// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MATERMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MATER", targets: ["MATER"])
    ],
    targets: [
        .executableTarget(
            name: "MATER",
            path: "Sources/MATER"
        )
    ]
)
