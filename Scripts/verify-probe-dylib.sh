#!/bin/bash
#
# Verifies that a built PlaybackProbe dynamic library still starts itself when
# dyld loads it.
#
# The probe relies on a load-time constructor in the C shim. Nothing in the
# application references that constructor, so a linker change or a packaging
# mistake can drop it and the probe would then fail silently: the library loads,
# no observer is registered, and every oracle reports "not playing". This check
# turns that silent failure into a build failure.
#
# Usage: Scripts/verify-probe-dylib.sh <path-to-dylib>

set -euo pipefail

dylib=${1:-}
if [[ -z "$dylib" ]]; then
    echo "usage: $0 <path-to-dylib>" >&2
    exit 2
fi
if [[ ! -f "$dylib" ]]; then
    echo "error: no such file: $dylib" >&2
    exit 2
fi

failed=0

# Read each tool's output once. Piping into `grep -q` would let grep exit early,
# hand the tool a SIGPIPE, and trip `pipefail` on a check that actually passed.
load_commands=$(otool -l "$dylib")
symbols=$(nm "$dylib")

if grep -qE '__init_offsets|__mod_init_func' <<<"$load_commands"; then
    echo "ok: image has an initialiser section"
else
    echo "FAIL: image has no initialiser section; the constructor was stripped" >&2
    failed=1
fi

if grep -qE '_playback_probe_bootstrap$' <<<"$symbols"; then
    echo "ok: bootstrap constructor is present"
else
    echo "FAIL: bootstrap constructor symbol is missing" >&2
    failed=1
fi

if grep -qE '_playback_probe_start$' <<<"$symbols"; then
    echo "ok: Swift entry point is exported"
else
    echo "FAIL: playback_probe_start is not exported" >&2
    failed=1
fi

exit "$failed"
