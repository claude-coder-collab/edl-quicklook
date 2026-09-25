// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EDLKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EDLKit", targets: ["EDLKit"])
    ],
    targets: [
        .target(name: "EDLKit"),
        .testTarget(
            name: "EDLKitTests",
            dependencies: ["EDLKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
