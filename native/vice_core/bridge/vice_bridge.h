/*
 * vice_bridge.h - Plain-C-ABI header for the VICE x64sc headless core bridge.
 *
 * No JNI, no C++, no Android types. Meant to be callable from dart:ffi
 * later, and (via a thin JNI shim, not written yet) from Java/Kotlin.
 */
#ifndef VICE_MULTIPLATFORM_VICE_BRIDGE_H
#define VICE_MULTIPLATFORM_VICE_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Media types passed to vice_core_start(). */
#define VICE_MEDIA_PRG 0
#define VICE_MEDIA_DISK 1
#define VICE_MEDIA_TAPE 2
#define VICE_MEDIA_NONE -1

/*
 * Set the ROM/data directory (must contain a "C64" subdirectory with
 * kernal/basic/chargen ROMs, same layout as
 * VICEAndroid/app/src/main/assets/vice/C64/). Must be called before
 * vice_core_start().
 */
void vice_core_init(const char *rom_dir);

/*
 * Start the VICE x64sc core on a background thread, or -- if the core is
 * already started -- hot-swap it to a different title.
 *
 * media_path may be NULL on the FIRST call (boot with no media attached);
 * on a subsequent call it is required, since a swap with no media has
 * nothing to load. Returns 0 on success (started, or swap queued), -1 on
 * failure. Asynchronous either way: on first start the core is still
 * running its startup sequence when this returns, and on a swap the actual
 * attach+autostart+reset happens on the core's own thread at the next
 * vsync (see apply_pending_media_if_any in vice_bridge.c).
 */
int32_t vice_core_start(int32_t media_type, const char *media_path, const char *command_line);

/* Trigger a power-cycle reset (soft "stop"). */
void vice_core_stop(void);

/* 1 if the core's main loop is currently running, 0 otherwise. */
int32_t vice_core_is_running(void);

/* Pause/resume the emulation (blocks the vsync loop while paused). */
void vice_core_set_paused(int32_t paused);

/* Logical C64 key id -> matrix row/column, as used by the Android bridge. */
void vice_core_key_event(int32_t key, int32_t pressed);

/* Direct C64 keyboard matrix row/column event. */
void vice_core_matrix_key_event(int32_t row, int32_t column, int32_t pressed);

/* port: 1 or 2. mask bits: 0x01 up, 0x02 down, 0x04 left, 0x08 right,
 * 0x10 fire1, 0x20 fire2. */
void vice_core_joystick(int32_t port, int32_t mask);

/* Attach a .d64/.d71/.d81/... disk image to drive 8. Returns 0 on success. */
int32_t vice_core_attach_disk(const char *path);

/* Attach a .tap/.t64 tape image to the datasette. Returns 0 on success. */
int32_t vice_core_attach_tape(const char *path);

/*
 * Returns a pointer to the internal RGBA8888 framebuffer (owned by the
 * bridge; do not free). out_width/out_height receive the current frame
 * dimensions. Returns NULL until at least one frame has been rendered.
 */
const uint32_t *vice_core_get_framebuffer(int32_t *out_width, int32_t *out_height);

/*
 * Write / read a real VICE machine snapshot (machine_write_snapshot /
 * machine_read_snapshot) so a title can be resumed at the exact cycle it
 * was left at.
 *
 * Both are SYNCHRONOUS from the caller's point of view but are executed on
 * the core's own mainloop thread via a mailbox (VICE machine state must
 * never be touched from another thread); the caller blocks until the core
 * reports back. Returns 0 on success, <0 on failure. Safe to call while the
 * emulation is paused -- the pause gate services these too.
 *
 * Named failures:
 *   VICE_SNAPSHOT_TIMEOUT           the core did not service the request
 *                                   within 10 seconds
 *   VICE_SNAPSHOT_UNSUPPORTED_MEDIA the currently attached media cannot be
 *                                   snapshotted in a way that will restore
 *                                   (see vice_core_can_snapshot). No file is
 *                                   written; the caller must offer the user a
 *                                   restart rather than a resume.
 */
#define VICE_SNAPSHOT_TIMEOUT (-2)
#define VICE_SNAPSHOT_UNSUPPORTED_MEDIA (-3)

int32_t vice_core_save_snapshot(const char *path);
int32_t vice_core_load_snapshot(const char *path);

/*
 * Can what is attached to the running machine right now be captured into a
 * snapshot that will actually restore?
 *
 * Returns 1 for yes, 0 for no, and -1 if the core is not running (unknown).
 * The one "no" this reports is a T64 tape image: VICE's tape snapshot code
 * (src/tape/tape-snapshot.c) has no T64 implementation at all and returns
 * success without writing the image, so the snapshot restores a datasette
 * pointing at nothing. Callers should use this to label a session "Restart"
 * instead of promising a "Resume" they cannot deliver.
 */
int32_t vice_core_can_snapshot(void);

/* Smoothed 0..100 audio peak level (dummy sound backend in this milestone). */
int32_t vice_core_get_audio_level(void);

/* Measured frames-per-second of the video refresh callback. */
int32_t vice_core_get_fps(void);

/* Tape and drive activity, for the loading indicators.
 *
 * These are fed by VICE's own status-bar callbacks (wrapped in the bridge),
 * so they only change while media is actually being read.
 *
 * vice_core_get_tape_counter    datasette position, the three-digit counter
 * vice_core_get_tape_motor      nonzero while the tape motor is running
 * vice_core_get_tape_control    DATASETTE_CONTROL_* (stop/play/rewind/...)
 * vice_core_get_drive_half_track  twice the head's track (36 == track 18)
 * vice_core_get_drive_led       drive LED intensity, 0..1000
 */
int32_t vice_core_get_tape_counter(void);
int32_t vice_core_get_tape_motor(void);
int32_t vice_core_get_tape_control(void);
int32_t vice_core_get_drive_half_track(void);
int32_t vice_core_get_drive_led(void);

#ifdef __cplusplus
}
#endif

#endif /* VICE_MULTIPLATFORM_VICE_BRIDGE_H */
