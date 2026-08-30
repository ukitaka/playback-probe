import Foundation
import PlaybackProbeHub

/// Runs the hub without the menu bar application.
///
/// Useful for CI, where there is no one to grant audio capture permission, and
/// for driving the state and time oracles from a machine that only needs the
/// aggregation point.

let arguments = CommandLine.arguments
let requestedPort = arguments
    .firstIndex(of: "--port")
    .flatMap { arguments.indices.contains($0 + 1) ? UInt16(arguments[$0 + 1]) : nil }
    ?? PlaybackHub.defaultPort

let hub = PlaybackHub(port: requestedPort)

do {
    try hub.start()
} catch {
    FileHandle.standardError.write(Data("playback-probe-hub: \(error)\n".utf8))
    exit(1)
}

// Printed on its own line and flushed so that a script can wait for the hub to
// be listening rather than sleeping a guessed amount.
print("listening on http://127.0.0.1:\(hub.port ?? requestedPort)")
fflush(stdout)

// Bound at the top level, so these live as long as the process. A signal source
// that goes out of scope is torn down, and the process would then ignore the
// signal outright, because the default disposition is replaced with SIG_IGN
// just below.
let signalSources = [SIGINT, SIGTERM].map { signalNumber -> DispatchSourceSignal in
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        hub.stop()
        exit(0)
    }
    source.resume()
    return source
}

_ = signalSources

dispatchMain()
