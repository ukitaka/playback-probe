# PlaybackProbe

Verify from a UI test that a video player really stopped.

When a modal, an advertisement or a system alert covers a video player, the
interesting question is whether playback behind it actually stopped. A
screenshot cannot answer that — the player is hidden, so a paused player and a
player that is still running look identical.

PlaybackProbe answers it by observing the player from inside the application
process and reporting what it sees to the test.

> **Status: early.** The state and time oracles work end to end on the iOS
> simulator. The audio and video oracles, the host-side capture app and the
> Android implementation are not built yet. See [Roadmap](#roadmap).

## Why not just read the player from the test?

XCUITest runs in a separate, sandboxed process. It can reach the accessibility
tree, screenshots and launch arguments, and nothing else — never the
application's memory. And in the case this exists for, the `AVPlayer` is owned
by a third-party online video platform SDK, so even code inside the application
has no reference to it.

PlaybackProbe is a dynamic library injected into the application at launch. A
load-time constructor registers an observer for
`AVPlayer.rateDidChangeNotification` with `object: nil`, which fires for *every*
`AVPlayer` in the process. The notification carries the instance, so the probe
gets a legitimate reference to a player nobody exposed.

## Oracles

No single signal is trustworthy on its own, so PlaybackProbe is designed around
several independent ones. Each catches bugs the others miss.

| Oracle | Source | What it proves | Status |
|---|---|---|---|
| State | `AVPlayer.timeControlStatus` | The player intends to be stopped | Implemented |
| Time | `AVPlayer.currentTime()`, sampled repeatedly | The playback position is not moving | Implemented |
| Audio | Core Audio process tap on the simulator's output | Nothing is reaching the speaker | Planned |
| Video | Frame differencing via `AVPlayerItemVideoOutput` | Rendering is not advancing | Planned |

Why more than one: a player whose state says `paused` while a second instance
keeps producing sound is invisible to the state and time oracles but obvious to
the audio oracle. A muted player still rendering video is the reverse. Every
single-oracle setup lets one of these through.

## Requirements

- iOS 16 or later, **simulator only**. A device rejects an injected library
  whose Team ID does not match the host application, and dyld silently ignores
  the environment variable.
- Xcode 16 or later.

## Usage

Add the package to the UI test target and inject it at launch:

```swift
let application = XCUIApplication()
application.launchEnvironment["DYLD_INSERT_LIBRARIES"] = probeLibraryPath
application.launchEnvironment["PLAYBACK_PROBE_ENABLED"] = "1"
application.launchEnvironment["PLAYBACK_PROBE_LOG_PATH"] = logPath
application.launch()
```

The application under test needs no source changes: dyld runs the library's
initialiser before `main()`, so the probe starts on its own.

The probe appends observations to `PLAYBACK_PROBE_LOG_PATH` as JSON Lines,
which the test reads while the application is still running:

```json
{"bootstrappedByConstructor":true,"kind":"probeStarted","timestamp":1756524000.1}
{"kind":"playerAttached","playerID":"player-1","playerState":"playing","timestamp":1756524001.0}
{"currentTime":1.53,"kind":"sample","playerID":"player-1","playerState":"playing","rate":1,"timestamp":1756524002.5}
```

The probe records evidence and nothing more. Deciding whether playback stopped
is left to the test, so the same samples can back different judgements.

### Configuration

All configuration is read from the process environment, because the probe is
injected into an application that knows nothing about it.

| Variable | Default | Meaning |
|---|---|---|
| `PLAYBACK_PROBE_ENABLED` | unset | Must be `1`, `true` or `yes`. The probe is completely inert otherwise. |
| `PLAYBACK_PROBE_LOG_PATH` | unset | Absolute path of the JSON Lines log. Without it, events only go to the unified log. |
| `PLAYBACK_PROBE_SAMPLE_INTERVAL_MS` | `500` | Sampling period for the state and time oracles. |

### Keeping it out of production

`PLAYBACK_PROBE_ENABLED` is the runtime guard: a build that links the probe by
accident does nothing at all unless a test explicitly enables it. Xcode's Swift
Package Manager integration cannot link a package for some build configurations
only, so if the probe must not ship at all, link it from a separate UI-test host
target rather than from the application.

## Example

`Examples/DemoApp` is a small application whose player is deliberately hidden
inside an SDK stand-in the tests cannot reach — the situation this toolkit
exists for. It has two overlay buttons that look identical once the overlay
covers the video: one pauses the player, the other forgets to. The UI tests
tell them apart.

```console
brew install xcodegen
cd Examples/DemoApp
xcodegen generate
xcodebuild test -project PlaybackProbeDemo.xcodeproj -scheme PlaybackProbeDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Known limits

- **Everything depends on catching the `AVPlayer`.** If the player renders
  through `AVSampleBufferDisplayLayer` or a custom Metal pipeline,
  `rateDidChangeNotification` never fires and the state, time and video oracles
  all go blind at once. Check this first against your own application; the
  audio oracle is the fallback when it fails.
- A player captured through the notification is not necessarily the instance
  producing sound. That is the specific gap the audio oracle closes.
- FairPlay-protected content blocks frame access. The simulator does not
  support FairPlay anyway, so this only matters for non-hermetic setups.

## Roadmap

1. ~~Injection: constructor, entry point, observer registration~~ — done
2. ~~State and time oracles, recorded to a log~~ — done
3. Host-side capture app: Core Audio process tap and RMS history
4. HTTP hub and a Swift client for the test side
5. Video oracle: `AVPlayerItemVideoOutput` frame differencing
6. Aggregate `/playback-status` with a cross-oracle consistency check
7. Android implementation behind the same schema

## License

MIT. See [LICENSE](LICENSE).
