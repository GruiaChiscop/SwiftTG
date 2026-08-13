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
                // Mirrors the original xcframework's module map, lost when the package was
                // repackaged from `.framework` (Xcode auto-embed issue) to a plain library target
                // (see ORIGIN.md) - SwiftPM synthesizes its own minimal module map for a directory
                // of headers, which doesn't carry the original's `link framework "..."` directives,
                // so every framework tgcalls needs has to be declared here instead.
                .linkedLibrary("c++"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
                .linkedLibrary("z"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreTelephony"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("GLKit"),
                .linkedFramework("Network"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("UIKit"),
                .linkedFramework("VideoToolbox"),
            ]
        ),
    ]
)
