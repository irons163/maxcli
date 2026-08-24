// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MaxCLI",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MaxCLI", targets: ["MaxCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.15.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "MaxCLI",
            dependencies: [
                "SwiftTerm",
                .product(name: "Sparkle", package: "sparkle")
            ],
            path: "Sources/MaxCLI",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MaxCLITests",
            dependencies: ["MaxCLI"],
            path: "Tests/MaxCLITests"
        )
    ]
)
