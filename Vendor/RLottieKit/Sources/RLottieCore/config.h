// SwiftPM configuration for TelegramMessenger/rlottie.
//
// The app drives synchronous frame rendering itself. Optional worker threads,
// the global model cache, and the dynamic image-loader module remain disabled.
// LOTTIE_THREAD_SAFE is supplied by Package.swift so synchronous renders use
// per-call rasterizer scratch storage.

// #define LOTTIE_MODULE
// #define LOTTIE_THREAD
// #define LOTTIE_CACHE
