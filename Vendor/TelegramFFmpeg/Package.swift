// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TelegramWebM",
    platforms: [
        .iOS(.v17),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "TelegramWebM", targets: ["TelegramWebM"]),
    ],
    targets: [
        .binaryTarget(
            name: "TelegramFFmpegBinary",
            path: "TelegramFFmpegBinary.xcframework"
        ),
        .target(
            name: "TelegramWebMCore",
            dependencies: ["TelegramFFmpegBinary"],
            path: "Sources/TelegramWebMCore",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Accelerate"),
            ]
        ),
        .target(
            name: "TelegramWebM",
            dependencies: ["TelegramWebMCore"],
            path: "Sources/TelegramWebM"
        ),
        .testTarget(
            name: "TelegramWebMTests",
            dependencies: ["TelegramWebM"],
            path: "Tests/TelegramWebMTests"
        ),
    ]
)
