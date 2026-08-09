// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MaxCLI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MaxCLI", targets: ["MaxCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "MaxCLI",
            dependencies: ["SwiftTerm"],
            path: "Sources/MaxCLI"
        ),
        .testTarget(
            name: "MaxCLITests",
            dependencies: ["MaxCLI"],
            path: "Tests/MaxCLITests"
        )
    ]
)
