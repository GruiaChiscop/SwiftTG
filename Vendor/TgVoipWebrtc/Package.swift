// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TgVoipWebrtc",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "TgVoipWebrtc", targets: ["TgVoipWebrtc"]),
    ],
    targets: [
        .binaryTarget(
            name: "TgVoipWebrtcBinary",
            path: "TgVoipWebrtc.xcframework"
        ),
        .target(
            name: "TgVoipWebrtc",
            dependencies: ["TgVoipWebrtcBinary"],
            path: "Sources/TgVoipWebrtc",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
