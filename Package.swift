// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Flight",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "Flight",
            targets: ["Flight"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.0"),
        .package(url: "https://github.com/DiscordBM/DiscordBM", exact: "1.16.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.9.0"),
    ],
    targets: [
        .target(
            name: "Flight",
            dependencies: [
                "COpus",
                "CSodium",
                "CLibdave",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources",
            exclude: ["COpus", "CSodium", "CLibdave", "CMLS", "CJson"],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .systemLibrary(
            name: "COpus",
            pkgConfig: "opus",
            providers: [
                .brew(["opus"]),
                .apt(["libopus-dev"]),
            ]
        ),
        .systemLibrary(
            name: "CSodium",
            pkgConfig: "libsodium",
            providers: [
                .brew(["libsodium"]),
                .apt(["libsodium-dev"]),
            ]
        ),
        .systemLibrary(
            name: "COpenSSL",
            pkgConfig: "openssl",
            providers: [
                .brew(["openssl@3"]),
                .apt(["libssl-dev"]),
            ]
        ),
        .target(
            name: "CLibdave",
            dependencies: [
                .target(name: "mlspp"),
                .target(name: "bytes"),
                .target(name: "tls_syntax"),
            ],
            path: "Sources/CLibdave",
            exclude: [
                "libdave/cpp/test",
                "libdave/cpp/src/mls/detail/persisted_key_pair_apple.cpp",
                "libdave/cpp/src/mls/detail/persisted_key_pair_win.cpp",
                "libdave/cpp/src/mls/persisted_key_pair_null.cpp",
                "libdave/cpp/src/bindings_wasm.cpp",
                "libdave/cpp/src/boringssl_cryptor.cpp",
                "libdave/cpp/src/boringssl_cryptor.h",
            ],
            sources: ["libdave/cpp/src"],
            cxxSettings: [
                .headerSearchPath("libdave/cpp/includes"),
                .headerSearchPath("libdave/cpp/src"),
            ]
        ),
        .target(
            name: "mlspp",
            dependencies: [
                .target(name: "hpke"),
                .target(name: "bytes"),
                .target(name: "tls_syntax"),
            ],
            path: "Sources/CMLS/mlspp",
            exclude: ["test"],
            sources: ["src"]
        ),
        .target(
            name: "mlspp_namespace",
            path: "Sources/CMLS/namespace",
            publicHeadersPath: "."
        ),
        .target(
            name: "hpke",
            dependencies: [
                .target(name: "mlspp_namespace"),
                .target(name: "bytes"),
                .target(name: "tls_syntax"),
                .target(name: "CJson"),
                "COpenSSL",
            ],
            path: "Sources/CMLS/mlspp/lib/hpke",
            exclude: ["test"],
            sources: ["src"],
            cxxSettings: [
                .define("WITH_OPENSSL3"),
            ]
        ),
        .target(
            name: "bytes",
            dependencies: [
                .target(name: "mlspp_namespace"),
                .target(name: "tls_syntax"),
            ],
            path: "Sources/CMLS/mlspp/lib/bytes",
            exclude: ["test"],
            sources: ["src"]
        ),
        .target(
            name: "tls_syntax",
            dependencies: [.target(name: "mlspp_namespace")],
            path: "Sources/CMLS/mlspp/lib/tls_syntax",
            exclude: ["test"],
            sources: ["src"]
        ),
        .target(
            name: "CJson",
            path: "Sources/CJson"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
