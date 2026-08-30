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
- Developed and tested with Xcode 26 and Swift 6. Earlier versions are untried.

## Usage

Link three products into the UI test target: `PlaybackProbe`, the dynamic
library that gets injected, plus `PlaybackProbeTestSupport` and
`PlaybackProbeXCTest`, which inject it and assert on what it saw.

```swift
import PlaybackProbeTestSupport
import PlaybackProbeXCTest

let logURL = try ProbeLogLocation.makeSharedLogURL()
let application = XCUIApplication()
application.launchEnvironment.merge(try ProbeLaunchEnvironment.make(logURL: logURL)) { _, new in new }
application.launch()

let log = ProbeEventLog(url: logURL)

application.buttons["play"].tap()
XCTAssertPlaybackStarts(log)

application.buttons["show-overlay"].tap()
XCTAssertPlaybackStops(log, "Playback continued behind the overlay")
```

The application under test needs no source changes: dyld runs the library's
initialiser before `main()`, so the probe starts on its own.

`ProbeLaunchEnvironment` fills in `DYLD_INSERT_LIBRARIES` by asking dyld which
image defines the probe's entry point, so it does not depend on where the build
put the library. `ProbeLogLocation` picks a path in the simulator device's
shared directory, because the application and the test runner have separate
containers.

### The assertions

Note that none of the above sleeps. Each assertion waits for its own evidence,
so a test never has to guess how long a state change takes to become visible.

| Assertion | Shape | Passes when |
|---|---|---|
| `XCTAssertPlaybackStarts(log)` | waits | Some window of samples shows the player playing *and* the position moving. |
| `XCTAssertPlaybackStops(log)` | waits | An entire window of samples reports paused *and* the position never moved. |
| `XCTAssertPlaybackContinues(log)` | watches a window | Playback ran for the whole window. |

`XCTAssertPlaybackContinues` deliberately does not wait. "Still playing" is a
claim about a stretch of time, and a wait would return the instant it saw a
single playing sample, which is a weaker claim than the one being made.

Every verdict needs both oracles to agree, which is what makes them worth more
than reading `timeControlStatus`. A player claiming `paused` while its position
climbs is not stopped, and a stalled player still claiming `playing` is not
playing.

For assertions in some other framework, `PlaybackProbeTestSupport` has the same
logic without XCTest: `waitUntilPlaybackStopped`, `waitUntilPlaybackStarted` and
`observePlayback(for:)` throw or return a `PlaybackObservation`.

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

## Package layout

| Product | Linked into | Purpose |
|---|---|---|
| `PlaybackProbe` | the test target, injected into the app | The probe itself. Dynamic, so dyld can load it. |
| `PlaybackProbeTestSupport` | the test target | Locating the library, building the launch environment, reading the log, reaching a verdict. |
| `PlaybackProbeXCTest` | the test target | XCTest assertions over the above. Separate so `PlaybackProbeTestSupport` stays usable without XCTest. |

`PlaybackProbeSchema` underneath both holds the wire types and carries no
platform assumptions, so the planned Android implementation can serve the same
schema.

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

## How soon can a test assert?

Short answer: use the assertions above and you do not have to care, because
they wait. This section is why they are shaped that way, and what to do if you
build your own.

A test that taps something and immediately asserts "playback stopped" is only
sound if the stop is already observable. Measured on the demo with
`PauseLatencyMeasurementTests`: 12 pause cycles per row across two runs, with
the moment of the pause randomised against the sampling timer so that the
measurement does not sit at one fixed phase.

| Sampling interval | Observable after `tap()` is called | Relative to `tap()` returning |
|---|---|---|
| 50ms | 128–248ms | −177 to −143ms |
| 200ms | 144–304ms | −174 to −4ms |
| 500ms (probe default) | 141–624ms | −178 to **+279ms** |

Figures are from an M-series Mac; a loaded machine will be slower.

Two things follow.

The pause itself is fast: about 140ms, most of which is XCUITest delivering the
tap. What a test waits for on top of that is the next sampling tick, which is
why the spread widens exactly in step with the interval.

XCUITest's own `tap()` takes around 310ms to return. At 200ms sampling or below,
the stop is therefore already in the log by the time the test regains control,
and "tap, then assert" is safe with no sleep at all. At the probe's 500ms
default it is not: the worst case observed landed 279ms *after* `tap()`
returned, which is a real flake. This is why `ProbeLaunchEnvironment` uses 200ms
rather than inheriting the probe's default.

The margin at 200ms is only a few milliseconds in the worst case, so a test
doing something faster than a tap, or running on a slower machine, cannot rely
on it. That is exactly the reasoning `XCTAssertPlaybackStops` removes: it polls
until the evidence is there rather than assuming it has arrived.

These figures cover the state and time oracles only. The audio oracle will add
the buffer still draining after a pause, which is a separate and larger delay.

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
