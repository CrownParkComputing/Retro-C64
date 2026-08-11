/*
 * vice_vsid_bridge.h - Plain-C-ABI header for the VICE vsid (standalone
 * SID-file player) core bridge.
 *
 * This is a from-scratch, non-JNI port of
 * ~/AndroidStudioProjects/VICEAndroid/app/src/main/cpp/vice_vsid_bridge.cpp
 * (kept as read-only reference; NOT modified), the same way vice_bridge.c
 * was ported from vice_android_bridge.cpp. It links libvsid.a/libvsidstubs.a
 * instead of libc64sc.a, so machine_class == VICE_MACHINE_VSID and real
 * PSID/RSID autostart + playback works (x64sc's PSID autodetection is
 * stubbed out).
 */
#ifndef VICE_MULTIPLATFORM_VICE_VSID_BRIDGE_H
#define VICE_MULTIPLATFORM_VICE_VSID_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Set the ROM/data directory (must contain a "C64" subdirectory with
 * kernal/basic/chargen ROMs). Must be called before vice_vsid_launch(). */
void vice_vsid_init(const char *rom_dir);

/*
 * Start the vsid core on a background thread with the given .sid/.psid file
 * as the initial tune (may be NULL/empty to boot vsid with nothing loaded).
 * If the core is already running, this instead hot-swaps in a new tune via
 * machine_autodetect_psid()/machine_play_psid() without restarting the
 * process. command_line is currently unused, reserved for parity with
 * vice_core_start(). Returns 0 on success, -1 on failure.
 */
int32_t vice_vsid_launch(const char *media_path, const char *command_line);

/* Pause/resume playback (blocks the vsync loop while paused). */
void vice_vsid_set_paused(int32_t paused);

/* 1 if the vsid mainloop is currently running, 0 otherwise. */
int32_t vice_vsid_is_running(void);

/* Smoothed 0..100 audio peak level, same shape as vice_core_get_audio_level. */
int32_t vice_vsid_get_audio_level(void);

/* vsid has no video canvas; always returns 0. Present for API parity. */
int32_t vice_vsid_get_fps(void);

#ifdef __cplusplus
}
#endif

#endif /* VICE_MULTIPLATFORM_VICE_VSID_BRIDGE_H */
