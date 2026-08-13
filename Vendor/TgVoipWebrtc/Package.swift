// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TgVoipWebrtc",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // This must remain a dynamic product. Both TDLib and tgcalls statically contain a crypto
        // implementation exporting the same OpenSSL `BN_*` symbols. Linking both archives into the
        // app lets ld satisfy TDLib's BigNum references with tgcalls' BoringSSL objects (or vice
        // versa), corrupting the DH validation before a call can ring (`Bad prime mod 4g`). A
        // separate Mach-O image gives each implementation its own two-level symbol namespace.
        .library(name: "TgVoipWebrtc", type: .dynamic, targets: ["TgVoipWebrtc"]),
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
                .linkedLibrary("objc"),
                .linkedLibrary("z"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreTelephony"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Foundation"),
                .linkedFramework("GLKit"),
                .linkedFramework("Metal"),
                .linkedFramework("Network"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("UIKit"),
                .linkedFramework("VideoToolbox"),
                // Without `-ObjC`, Objective-C *categories* in a statically-linked library don't
                // get loaded at all (unlike classes) - the linker only pulls in object files that
                // define a symbol something else already references, and a category doesn't count.
                // tgcalls adds `maxSupportedH264Profile` as a category on `UIDevice`; without this
                // flag it crashes at runtime with "unrecognized selector" the first time anything
                // touches it, even though the build and link both succeed.
                .unsafeFlags(["-Xlinker", "-ObjC"]),
            ]
        ),
    ]
)
