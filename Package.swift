// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlaybackProbe",
    platforms: [
        .iOS(.v16),
        // Core Audio process taps, which the audio oracle needs, arrived in
        // macOS 14.4. Only the host-side targets are affected.
        .macOS("14.4"),
    ],
    products: [
        // Must stay `.dynamic`: the probe is loaded with DYLD_INSERT_LIBRARIES,
        // and a static product would let the linker drop the unreferenced
        // bootstrap constructor.
        .library(
            name: "PlaybackProbe",
            type: .dynamic,
            targets: ["PlaybackProbe", "ProbeBootstrap"]
        ),
        // Helpers for the test side: locating the injected library, building
        // the launch environment and reading back what the probe recorded.
        .library(name: "PlaybackProbeTestSupport", targets: ["PlaybackProbeTestSupport"]),
        // XCTest assertions built on the helpers above. Separate so that
        // PlaybackProbeTestSupport stays usable without XCTest.
        .library(name: "PlaybackProbeXCTest", targets: ["PlaybackProbeXCTest"]),
        // The host-side aggregation point: an HTTP endpoint every oracle
        // reports to and the test reads from.
        .library(name: "PlaybackProbeHub", targets: ["PlaybackProbeHub"]),
        // The audio oracle: taps what the Mac is playing and reports its level.
        .library(name: "PlaybackProbeAudio", targets: ["PlaybackProbeAudio"]),
        // Runs the hub headlessly, without the menu bar application.
        .executable(name: "playback-probe-hub", targets: ["playback-probe-hub"]),
    ],
    targets: [
        // C shim holding the `__attribute__((constructor))` entry point.
        // Swift cannot override `+load`, so the entry point lives in C and
        // calls into Swift through an `@_cdecl` symbol.
        .target(name: "ProbeBootstrap"),
        // The wire contract: no AVFoundation, no platform assumptions, so the
        // Android implementation can serve the same schema.
        .target(name: "PlaybackProbeSchema"),
        .target(name: "PlaybackProbe", dependencies: ["ProbeBootstrap", "PlaybackProbeSchema"]),
        .target(name: "PlaybackProbeTestSupport", dependencies: ["PlaybackProbeSchema"]),
        .target(name: "PlaybackProbeHub", dependencies: ["PlaybackProbeSchema"]),
        .target(name: "PlaybackProbeAudio"),
        .executableTarget(
            name: "playback-probe-hub",
            dependencies: ["PlaybackProbeHub", "PlaybackProbeAudio"]
        ),
        .target(
            name: "PlaybackProbeXCTest",
            dependencies: ["PlaybackProbeSchema", "PlaybackProbeTestSupport"]
        ),
        .testTarget(
            name: "PlaybackProbeTests",
            dependencies: ["PlaybackProbeSchema", "PlaybackProbeTestSupport"]
        ),
        .testTarget(name: "PlaybackProbeAudioTests", dependencies: ["PlaybackProbeAudio"]),
        .testTarget(
            name: "PlaybackProbeHubTests",
            dependencies: ["PlaybackProbeHub", "PlaybackProbeSchema", "PlaybackProbeTestSupport"]
        ),
    ]
)
