// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundboardBot",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/DiscordBM/DiscordBM", from: "1.16.0"),
        .package(url: "https://github.com/debaucheryparty/Flight.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SoundboardBot",
            dependencies: [
                .product(name: "DiscordBM", package: "DiscordBM"),
                .product(name: "Flight", package: "Flight"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ],
        ),
    ],
)
