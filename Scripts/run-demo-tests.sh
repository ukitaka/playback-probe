#!/bin/bash
#
# Runs the demo's UI tests with a hub listening on the host.
#
# The hub cannot live in the test runner: an iOS process cannot reliably hold a
# listening socket while it is in the background, which is where the XCUITest
# runner sits whenever the application under test is in front. Simulator
# processes share the host's loopback, so a hub started here is reachable from
# both the application and the runner at 127.0.0.1.
#
# Usage: Scripts/run-demo-tests.sh [additional xcodebuild arguments]

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
destination=${PLAYBACK_PROBE_DESTINATION:-platform=iOS Simulator,name=iPhone 17}
port=${PLAYBACK_PROBE_HUB_PORT:-8642}
# PLAYBACK_PROBE_AUDIO=1 also runs the audio oracle. It needs audio capture
# permission, and the simulator only produces sound while Simulator.app is
# running, so a headless boot is silent.
audio_arguments=()
if [[ "${PLAYBACK_PROBE_AUDIO:-0}" == "1" ]]; then
    audio_arguments+=(--audio)
    if [[ -n "${PLAYBACK_PROBE_AUDIO_PROCESS:-}" ]]; then
        audio_arguments+=(--audio-process "$PLAYBACK_PROBE_AUDIO_PROCESS")
    fi
    open -a Simulator
fi
log=$(mktemp -t playback-probe-hub)

cleanup() {
    if [[ -n "${hub_pid:-}" ]] && kill -0 "$hub_pid" 2>/dev/null; then
        kill "$hub_pid" 2>/dev/null || true
        wait "$hub_pid" 2>/dev/null || true
    fi
    rm -f "$log"
}
trap cleanup EXIT

echo "==> Building the hub"
swift build --package-path "$root" --product playback-probe-hub

echo "==> Starting the hub on port $port"
swift run --package-path "$root" playback-probe-hub --port "$port" "${audio_arguments[@]}" >"$log" 2>&1 &
hub_pid=$!

# Wait for the line the hub prints once it is listening, rather than sleeping a
# guessed amount.
for _ in $(seq 1 50); do
    if grep -q "listening on" "$log"; then break; fi
    if ! kill -0 "$hub_pid" 2>/dev/null; then
        echo "The hub exited before it started listening:" >&2
        cat "$log" >&2
        exit 1
    fi
    sleep 0.2
done
if ! grep -q "listening on" "$log"; then
    echo "The hub did not start listening in time:" >&2
    cat "$log" >&2
    exit 1
fi
cat "$log"

echo "==> Generating the demo project"
(cd "$root/Examples/DemoApp" && xcodegen generate >/dev/null)

echo "==> Running the UI tests"
# The TEST_RUNNER_ prefix is stripped before the runner sees the variable.
TEST_RUNNER_PLAYBACK_PROBE_HUB_URL="http://127.0.0.1:$port" \
    xcodebuild test \
    -project "$root/Examples/DemoApp/PlaybackProbeDemo.xcodeproj" \
    -scheme PlaybackProbeDemo \
    -destination "$destination" \
    "$@"
