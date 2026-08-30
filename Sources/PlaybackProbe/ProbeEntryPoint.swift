import Foundation

/// Entry point called from the `ProbeBootstrap` load-time constructor.
///
/// Swift cannot express `__attribute__((constructor))` and cannot override
/// `+load`, so the constructor lives in C and reaches Swift through this
/// exported C symbol.
@_cdecl("playback_probe_start")
public func playback_probe_start() {
    PlaybackProbe.shared.start()
}
