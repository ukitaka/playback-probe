// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlaybackProbe",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
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
        .testTarget(
            name: "PlaybackProbeTests",
            dependencies: ["PlaybackProbeSchema", "PlaybackProbeTestSupport"]
        ),
    ]
)
