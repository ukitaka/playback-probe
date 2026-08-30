#include "ProbeBootstrap.h"

static bool bootstrap_did_run = false;

/// dyld runs every Mach-O image's `__mod_init_func` entries before `main()`,
/// so injecting this library with DYLD_INSERT_LIBRARIES is enough to start the
/// probe. The host application needs no source changes.
__attribute__((constructor))
static void playback_probe_bootstrap(void) {
    bootstrap_did_run = true;
    playback_probe_start();
}

bool playback_probe_bootstrap_did_run(void) {
    return bootstrap_did_run;
}
