// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RLottieKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "RLottieKit", targets: ["RLottieKit"]),
    ],
    targets: [
        .target(
            name: "RLottieCore",
            path: "Sources/RLottieCore",
            exclude: [
                // The engine is an unmodified checkout of TelegramMessenger/rlottie.
                // Keep its build system, examples, tests, and C API outside this
                // SwiftPM target; RLottieKit uses the C++ interface directly.
                "rlottie/.Gifs",
                "rlottie/example",
                "rlottie/test",
                "rlottie/cmake",
                "rlottie/packaging",
                "rlottie/vs2019",
                "rlottie/licenses",
                "rlottie/COPYING",
                "rlottie/AUTHORS",
                "rlottie/README.md",
                "rlottie/inc/rlottie_capi.h",
                "rlottie/src/binding",
                // The NEON implementation calls external pixman assembly. SwiftPM
                // does not assemble that source, so use rlottie's scalar fallback.
                "rlottie/src/vector/vdrawhelper_neon.cpp",
                "rlottie/src/vector/pixman/pixman-arm-neon-asm.S",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("rlottie/inc"),
                .headerSearchPath("rlottie/src"),
                .headerSearchPath("rlottie/src/lottie"),
                .headerSearchPath("rlottie/src/vector"),
                .headerSearchPath("rlottie/src/vector/freetype"),
                .headerSearchPath("rlottie/src/vector/pixman"),
                .headerSearchPath("rlottie/src/vector/stb"),
                .define("LOT_BUILD"),
                .define("NDEBUG"),
                // BetterTG can render several stickers concurrently. With the
                // engine's worker pool disabled, this keeps rasterizer scratch
                // storage local to each render instead of sharing it globally.
                .define("LOTTIE_THREAD_SAFE"),
                // Disable NEON intrinsics: vdrawhelper_neon.cpp is excluded (it pulls
                // in pixman .S assembly that SPM won't assemble). Undefining __ARM_NEON__
                // activates the scalar memfill32 fallback in vdrawhelper.cpp and prevents
                // RenderFuncTable::RenderFuncTable() from calling the missing neon() stub.
                // Xcode defines DEBUG for Debug configurations, but upstream's
                // embedded pixman region file has no debug self-check function.
                .unsafeFlags(["-U__ARM_NEON__", "-UDEBUG"]),
            ]
        ),
        .target(
            name: "RLottieKit",
            dependencies: ["RLottieCore"],
            path: "Sources/RLottieKit",
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "RLottieKitTests",
            dependencies: ["RLottieKit"],
            path: "Tests/RLottieKitTests",
            resources: [
                .copy("Resources/tiny.tgs"),
                .copy("Resources/tiny.json"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
