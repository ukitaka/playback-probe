import Foundation
import PlaybackProbeAudio
import PlaybackProbeHub

/// Runs the hub without the menu bar application.
///
/// Useful for CI, where there is no one to grant audio capture permission, and
/// for driving the state and time oracles from a machine that only needs the
/// aggregation point.

let arguments = CommandLine.arguments

// Discovery step: which process carries the simulator's sound is not
// documented and differs between setups. Play something, then look at what is
// producing output.
if arguments.contains("--list-audio-processes") {
    do {
        let processes = try AudioProcess.all().sorted {
            ($0.isProducingOutput ? 0 : 1, $0.bundleIdentifier ?? "") <
                ($1.isProducingOutput ? 0 : 1, $1.bundleIdentifier ?? "")
        }
        for process in processes {
            print(process.description)
        }
        print("\n\(processes.filter(\.isProducingOutput).count) of \(processes.count) producing output")
    } catch {
        FileHandle.standardError.write(Data("playback-probe-hub: \(error)\n".utf8))
        exit(1)
    }
    exit(0)
}

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

// Optional because the tap needs audio capture permission, which the system
// only ever grants to a signed application bundle. From a bare executable this
// is expected to fail; the message says so.
let tap: AudioLevelTap? = arguments.contains("--audio") ? AudioLevelTap() : nil

if let tap {
    do {
        try tap.start { level in
            hub.store.audioLevels.append(
                AudioLevelSample(timestamp: Date().timeIntervalSince1970, rms: level)
            )
        }
        hub.store.isAudioTapAttached = true
        print("audio tap running")
    } catch {
        FileHandle.standardError.write(Data("playback-probe-hub: \(error)\n".utf8))
        exit(1)
    }
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
        tap?.stop()
        hub.stop()
        exit(0)
    }
    source.resume()
    return source
}

_ = signalSources

dispatchMain()
