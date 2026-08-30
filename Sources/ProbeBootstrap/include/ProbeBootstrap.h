#ifndef PROBE_BOOTSTRAP_H
#define PROBE_BOOTSTRAP_H

#include <stdbool.h>

/// Implemented in Swift and exported as a C symbol via `@_cdecl`.
///
/// Called from a load-time constructor, which dyld runs before `main()`. At
/// that point UIKit is not initialised, so the implementation must only
/// register observers and must not touch the UI.
extern void playback_probe_start(void);

/// Reports whether the load-time constructor ran.
///
/// Distinguishes "injected with DYLD_INSERT_LIBRARIES" from "linked into the
/// application and started by hand", which tells a failing test whether it has
/// an injection problem or an observation problem.
///
/// This is also the only Swift-visible symbol in this translation unit. Should
/// a future toolchain link the C target as an archive rather than as loose
/// object files, that reference is what would keep the constructor in the
/// image. `Scripts/verify-probe-dylib.sh` guards against it disappearing.
bool playback_probe_bootstrap_did_run(void);

#endif /* PROBE_BOOTSTRAP_H */
