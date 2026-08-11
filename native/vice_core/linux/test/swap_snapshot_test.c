/*
 * swap_snapshot_test.c - Verifies the two core-thread mailboxes in
 * vice_bridge.c: media hot-swap (vice_core_start on an already-started
 * core) and machine snapshots (vice_core_save_snapshot /
 * vice_core_load_snapshot).
 *
 * Both are checked against the framebuffer rather than against a return
 * code alone, because "the call returned 0" is exactly the kind of evidence
 * that was previously hiding a snapshot restore that did nothing: VICE
 * happily reported 0 from machine_read_snapshot while the emulated CPU
 * carried straight on from where it already was.
 *
 *   1. boot title A (required to have a STILL screen) and capture it
 *   2. save a snapshot, then drive the machine somewhere else with real
 *      input -> the picture MUST change, or there is nothing to rewind
 *   3. load the snapshot back into the SAME session
 *      -> the picture MUST return to the save-point frame
 *   4. hot-swap to title B -> the picture MUST change
 *   5. load title A's snapshot back while title B is running
 *      -> the picture MUST return to title A's save point. This is the
 *         one that mirrors the app's actual Resume flow, where the user
 *         has played something else in between, and it is the only step
 *         that exercises whether the media (disk image, tape) travelled
 *         inside the snapshot rather than merely being still attached.
 *
 * Step 1's stillness requirement is load-bearing. An animated title screen
 * (1942's, for one) repaints ~49% of its pixels every 250ms, so ANY two
 * captures of it differ by about that much whether or not the restore
 * worked -- a comparison against it cannot distinguish success from
 * failure. Driving the state change with input instead of with elapsed
 * time also makes step 3 test the thing that matters: that the restore
 * rewinds real machine state, not merely the video output.
 *
 * A title this harness cannot set up a valid before/after for (animated
 * screen, or input that never changes the picture) is reported as SKIP,
 * with the reason, and does NOT count as a pass.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "vice_bridge.h"

static void sleep_ms(long ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

#define MAX_PIXELS (1024 * 1024)

/* How close a restored frame must be to the save point. Not zero: a title
 * that keeps a blinking cursor or a colour cycle running will differ in a
 * handful of pixels no matter how perfect the restore. In practice a
 * correct restore of a still screen scores 0.0000 and a broken one scores
 * 0.3 - 1.0, so anything in between is a real regression. */
#define RESTORE_TOLERANCE 0.02

/* How much of the emulated machine (compared module by module, see
 * snapshot_difference) may still differ after a restore. A correct restore
 * measures ~0.0002 here -- the free-running clock in MAINCPU/CIA1 and a
 * handful of RAM bytes for the frame that elapses between the restore and
 * the verification snapshot -- while a restore that did nothing measures
 * whatever the drift was, typically 0.2 and up. 0.01 sits two orders of
 * magnitude clear of the good case and twenty times below the bad one. */
#define STATE_RESTORE_TOLERANCE 0.01

typedef struct {
    int width;
    int height;
    uint32_t pixels[MAX_PIXELS];
} frame_copy_t;

static frame_copy_t g_a, g_b, g_saved, g_drifted, g_restored, g_restored_cross;

static int capture(frame_copy_t *out) {
    int32_t w = 0, h = 0;
    const uint32_t *fb = vice_core_get_framebuffer(&w, &h);
    if (fb == NULL || w <= 0 || h <= 0 || (size_t)w * (size_t)h > MAX_PIXELS) {
        return 0;
    }
    out->width = w;
    out->height = h;
    memcpy(out->pixels, fb, (size_t)w * (size_t)h * sizeof(uint32_t));
    return 1;
}

/* Fraction of pixels that differ, 0.0 .. 1.0. */
static double frame_difference(const frame_copy_t *a, const frame_copy_t *b) {
    if (a->width != b->width || a->height != b->height) return 1.0;
    const size_t n = (size_t)a->width * (size_t)a->height;
    size_t differing = 0;
    for (size_t i = 0; i < n; i++) {
        if (a->pixels[i] != b->pixels[i]) differing++;
    }
    return n == 0 ? 1.0 : (double)differing / (double)n;
}

/* Writes a capture out as a binary PPM so a failing run leaves something
 * you can actually look at, instead of only a difference ratio. */
static void dump_ppm(const frame_copy_t *frame, const char *name) {
    char path[512];
    snprintf(path, sizeof(path), "/tmp/vice_swap_test_%s.ppm", name);
    FILE *f = fopen(path, "wb");
    if (f == NULL) return;
    fprintf(f, "P6\n%d %d\n255\n", frame->width, frame->height);
    const size_t n = (size_t)frame->width * (size_t)frame->height;
    for (size_t i = 0; i < n; i++) {
        const uint32_t px = frame->pixels[i];
        const uint8_t rgb[3] = {
            (uint8_t)(px & 0xff),
            (uint8_t)((px >> 8) & 0xff),
            (uint8_t)((px >> 16) & 0xff),
        };
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
    printf("[swap_snapshot_test] wrote %s\n", path);
}

/* Reads a whole file. Returns NULL on failure; caller frees. */
static uint8_t *read_file(const char *path, size_t *out_size) {
    FILE *f = fopen(path, "rb");
    if (f == NULL) return NULL;
    fseek(f, 0, SEEK_END);
    const long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size <= 0) { fclose(f); return NULL; }
    uint8_t *buf = malloc((size_t)size);
    if (buf == NULL) { fclose(f); return NULL; }
    const size_t got = fread(buf, 1, (size_t)size, f);
    fclose(f);
    if (got != (size_t)size) { free(buf); return NULL; }
    *out_size = got;
    return buf;
}

/* --- VICE .vsf parsing ------------------------------------------------- *
 *
 * A snapshot is a 58-byte file header followed by modules, each of which is
 * a 16-byte NUL-padded name, a major and minor version byte, a 32-bit
 * little-endian total size (header included), then the payload. See
 * snapshot_create() / snapshot_module_create() in VICE's src/snapshot.c. */
#define SNAPSHOT_FILE_HEADER_LEN 58
#define SNAPSHOT_MODULE_NAME_LEN 16
#define SNAPSHOT_MODULE_HEADER_LEN 22
#define MAX_SNAPSHOT_MODULES 128

typedef struct {
    char name[SNAPSHOT_MODULE_NAME_LEN + 1];
    const uint8_t *payload;
    size_t payload_size;
} snapshot_module_ref_t;

typedef struct {
    uint8_t *data;
    size_t size;
    snapshot_module_ref_t modules[MAX_SNAPSHOT_MODULES];
    int count;
} parsed_snapshot_t;

static int parse_snapshot(const char *path, parsed_snapshot_t *out) {
    memset(out, 0, sizeof(*out));
    out->data = read_file(path, &out->size);
    if (out->data == NULL || out->size < SNAPSHOT_FILE_HEADER_LEN) {
        free(out->data);
        out->data = NULL;
        return 0;
    }
    size_t off = SNAPSHOT_FILE_HEADER_LEN;
    while (off + SNAPSHOT_MODULE_HEADER_LEN <= out->size &&
           out->count < MAX_SNAPSHOT_MODULES) {
        const uint8_t *header = out->data + off;
        const uint32_t size = (uint32_t)header[18] | ((uint32_t)header[19] << 8) |
                              ((uint32_t)header[20] << 16) | ((uint32_t)header[21] << 24);
        if (size < SNAPSHOT_MODULE_HEADER_LEN || off + size > out->size) {
            break;
        }
        snapshot_module_ref_t *module = &out->modules[out->count++];
        memcpy(module->name, header, SNAPSHOT_MODULE_NAME_LEN);
        module->name[SNAPSHOT_MODULE_NAME_LEN] = '\0';
        module->payload = header + SNAPSHOT_MODULE_HEADER_LEN;
        module->payload_size = size - SNAPSHOT_MODULE_HEADER_LEN;
        off += size;
    }
    return out->count > 0;
}

static const snapshot_module_ref_t *find_module(const parsed_snapshot_t *snap,
                                                 const char *name) {
    for (int i = 0; i < snap->count; i++) {
        if (strcmp(snap->modules[i].name, name) == 0) return &snap->modules[i];
    }
    return NULL;
}

/* Fraction of machine-state bytes that differ between two snapshot files,
 * 0.0 .. 1.0, compared MODULE BY MODULE.
 *
 * This is the media-independent way to judge a restore, and the only way to
 * judge one for a title whose screen never stops moving.
 *
 * Comparing the files as flat byte streams does not work, and quietly
 * reports a perfect restore as a 13% mismatch: restoring across titles can
 * leave one extra 22-byte module (VDRIVEIMAGE8, after a disk title has been
 * mounted) in the re-saved file, and those 22 bytes shift every module after
 * them out of alignment. Matching modules up by name first makes the measure
 * mean what it claims: how much of the emulated machine actually differs. */
static double snapshot_difference(const char *path_a, const char *path_b) {
    parsed_snapshot_t a, b;
    if (!parse_snapshot(path_a, &a)) { free(a.data); return 1.0; }
    if (!parse_snapshot(path_b, &b)) { free(a.data); free(b.data); return 1.0; }

    size_t differing = 0, total = 0;
    for (int i = 0; i < a.count; i++) {
        const snapshot_module_ref_t *x = &a.modules[i];
        const snapshot_module_ref_t *y = find_module(&b, x->name);
        if (y == NULL) {
            differing += x->payload_size;
            total += x->payload_size;
            continue;
        }
        const size_t n = x->payload_size < y->payload_size ? x->payload_size
                                                            : y->payload_size;
        const size_t longest = x->payload_size > y->payload_size ? x->payload_size
                                                                 : y->payload_size;
        differing += longest - n;
        for (size_t k = 0; k < n; k++) {
            if (x->payload[k] != y->payload[k]) differing++;
        }
        total += longest;
    }
    /* Modules only the second file has count too -- a restore that leaves
     * whole chunks of a previous title's machine behind is not a restore. */
    for (int i = 0; i < b.count; i++) {
        if (find_module(&a, b.modules[i].name) == NULL) {
            differing += b.modules[i].payload_size;
            total += b.modules[i].payload_size;
        }
    }

    free(a.data);
    free(b.data);
    return total == 0 ? 1.0 : (double)differing / (double)total;
}

static int fail(const char *msg) {
    fprintf(stderr, "[swap_snapshot_test] FAIL: %s\n", msg);
    fflush(stderr);
    return 1;
}

/* Not a pass. The harness could not construct a meaningful check for this
 * input, and says so out loud rather than printing PASS over the top of a
 * test that never ran. Exit code 77 is the automake/ctest convention for
 * "skipped", so a harness can tell it apart from both 0 (pass) and 1 (fail)
 * without parsing the output. */
static int skip(const char *msg) {
    printf("[swap_snapshot_test] SKIP: %s\n", msg);
    fflush(stdout);
    return 77;
}

/* Try, in order, the inputs most likely to move a C64 title off a start
 * screen, stopping at the first one that visibly changes the picture. A
 * fixed F1 press only works for titles that happen to use F1. */
static int drive_machine_off_start_screen(const frame_copy_t *from,
                                          frame_copy_t *out, double *out_diff) {
    /* Key ordinals per c64_matrix_key() in vice_bridge.c. */
    static const struct { int key; const char *name; } keys[] = {
        { 3, "F1" },
        { 0, "SPACE" },
        { 2, "RETURN" },
        { 6, "F7" },
    };

    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        printf("[swap_snapshot_test] trying %s to leave the start screen\n",
               keys[i].name);
        vice_core_key_event(keys[i].key, 1);
        sleep_ms(120);
        vice_core_key_event(keys[i].key, 0);
        sleep_ms(4000);
        if (!capture(out)) return 0;
        const double diff = frame_difference(from, out);
        printf("[swap_snapshot_test]   after %s: %.4f\n", keys[i].name, diff);
        if (diff >= 0.05) {
            *out_diff = diff;
            return 1;
        }
    }

    /* Joystick fire, port 2 -- what most games actually want. */
    printf("[swap_snapshot_test] trying joystick fire to leave the start screen\n");
    vice_core_joystick(2, 0x10);
    sleep_ms(200);
    vice_core_joystick(2, 0);
    sleep_ms(4000);
    if (!capture(out)) return 0;
    const double diff = frame_difference(from, out);
    printf("[swap_snapshot_test]   after FIRE: %.4f\n", diff);
    if (diff >= 0.05) {
        *out_diff = diff;
        return 1;
    }
    *out_diff = diff;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr,
                "usage: %s <rom_dir> <title_a> <title_b> [snapshot_out]\n"
                "  title_a/title_b: \"<type>:<path>\" where type is prg|disk|tape\n",
                argv[0]);
        return 2;
    }
    const char *rom_dir = argv[1];
    const char *snapshot_path = argc > 4 ? argv[4] : "/tmp/vice_swap_snapshot_test.vsf";

    int types[2];
    const char *paths[2];
    for (int i = 0; i < 2; i++) {
        const char *spec = argv[2 + i];
        const char *colon = strchr(spec, ':');
        if (colon == NULL) return fail("title spec must be <type>:<path>");
        paths[i] = colon + 1;
        if (strncmp(spec, "prg", 3) == 0) types[i] = VICE_MEDIA_PRG;
        else if (strncmp(spec, "disk", 4) == 0) types[i] = VICE_MEDIA_DISK;
        else if (strncmp(spec, "tape", 4) == 0) types[i] = VICE_MEDIA_TAPE;
        else return fail("unknown media type in title spec");
    }

    vice_core_init(rom_dir);

    /* --- 1. boot title A ------------------------------------------------ */
    printf("[swap_snapshot_test] starting title A: %s\n", paths[0]);
    if (vice_core_start(types[0], paths[0], NULL) != 0) {
        return fail("vice_core_start(A) returned nonzero");
    }
    int running = 0;
    for (int i = 0; i < 150; i++) {
        if (vice_core_is_running()) { running = 1; break; }
        sleep_ms(100);
    }
    if (!running) return fail("core never reported running");

    /* Long enough for the autostart state machine to finish loading and for
     * the title to be putting real pixels on screen. */
    sleep_ms(25000);
    if (!capture(&g_a)) return fail("no framebuffer after title A");
    printf("[swap_snapshot_test] title A frame %dx%d\n", g_a.width, g_a.height);
    dump_ppm(&g_a, "title_a");

    /* --- 2. snapshot round-trip on title A ------------------------------ */
    if (!capture(&g_saved)) return fail("no framebuffer at save point");
    dump_ppm(&g_saved, "saved");

    static frame_copy_t still_check;
    sleep_ms(500);
    if (!capture(&still_check)) return fail("no framebuffer for stillness check");
    const double stillness = frame_difference(&g_saved, &still_check);
    /* A still screen lets the restore be judged from the picture, which is
     * the evidence a user would accept. An animated one does not -- 1942's
     * title repaints ~49% of its pixels every 250ms, so any two captures
     * differ by about that much whether or not the restore worked. Those
     * titles are still fully tested, just by comparing snapshot files
     * instead of frames (see snapshot_difference above); only the pixel
     * assertions are dropped. */
    const int still_screen = stillness <= RESTORE_TOLERANCE;
    printf("[swap_snapshot_test] title A natural motion over 500ms: %.4f (%s)\n",
           stillness,
           still_screen ? "still screen: frames and snapshot files both checked"
                        : "animated screen: snapshot files checked, frames not");

    const int32_t save_result = vice_core_save_snapshot(snapshot_path);
    printf("[swap_snapshot_test] save_snapshot(%s) -> %d\n", snapshot_path, save_result);
    if (save_result == VICE_SNAPSHOT_UNSUPPORTED_MEDIA) {
        return skip("the core refuses to snapshot this title's media (see the "
                    "VICEBridge log line above for which part). That is the "
                    "honest answer, not a failure -- the app is expected to "
                    "offer Restart rather than Resume for it.");
    }
    if (save_result != 0) return fail("vice_core_save_snapshot failed");

    FILE *f = fopen(snapshot_path, "rb");
    if (f == NULL) return fail("snapshot file was not created");
    fseek(f, 0, SEEK_END);
    const long snapshot_size = ftell(f);
    fclose(f);
    printf("[swap_snapshot_test] snapshot size: %ld bytes\n", snapshot_size);
    if (snapshot_size < 1024) return fail("snapshot file is implausibly small");

    char drift_path[1200], restored_path[1200];
    snprintf(drift_path, sizeof(drift_path), "%s.drift", snapshot_path);
    snprintf(restored_path, sizeof(restored_path), "%s.restored", snapshot_path);

    double moved = 0.0;
    const int picture_moved =
        drive_machine_off_start_screen(&g_saved, &g_drifted, &moved);
    dump_ppm(&g_drifted, "after_input");
    if (still_screen && !picture_moved) {
        return skip("no input this harness knows how to send changed title A's "
                    "picture, so there is nothing for a restore to rewind and "
                    "the round-trip cannot be judged. Re-run with a title that "
                    "reacts to a keypress or to fire.");
    }
    printf("[swap_snapshot_test] after input vs save point: %.4f\n", moved);

    /* The machine's state at the drifted point, as a file. This is what the
     * restore has to undo, and comparing against it is how a title with a
     * moving screen is judged. */
    if (vice_core_save_snapshot(drift_path) != 0) {
        return fail("could not save the drifted-point snapshot");
    }
    const double drift_delta = snapshot_difference(snapshot_path, drift_path);
    printf("[swap_snapshot_test] machine state moved by %.4f of snapshot bytes\n",
           drift_delta);
    if (drift_delta < 0.001) {
        return skip("the machine barely changed after several seconds and "
                    "every input this harness knows, so there is nothing for a "
                    "restore to rewind. Re-run with a title that reacts.");
    }

    /* --- 3. load the snapshot back into the same session ---------------- */
    const int32_t load_result = vice_core_load_snapshot(snapshot_path);
    printf("[swap_snapshot_test] load_snapshot -> %d\n", load_result);
    if (load_result != 0) return fail("vice_core_load_snapshot failed");
    /* vice_core_load_snapshot already waits for the restored machine to draw
     * fresh frames before returning, so no sleep is needed here; a short one
     * remains only to let a title's first restored frame settle. */
    sleep_ms(300);
    if (!capture(&g_restored)) return fail("no framebuffer after restore");
    dump_ppm(&g_restored, "restored");

    if (still_screen) {
        const double restored_vs_save = frame_difference(&g_saved, &g_restored);
        printf("[swap_snapshot_test] restored vs save point: %.4f "
               "(post-input was %.4f)\n", restored_vs_save, moved);
        if (restored_vs_save > RESTORE_TOLERANCE) {
            return fail("restored frame does not match the save point -- the "
                        "snapshot did not restore the machine state");
        }
    }

    /* Snapshot the restored machine and compare it back against the original.
     * A working restore lands within a frame's worth of cycles of the save
     * point, so this is far smaller than drift_delta; a broken one leaves the
     * machine wherever it already was, so it is about the same size. */
    if (vice_core_save_snapshot(restored_path) != 0) {
        return fail("could not save the restored-point snapshot");
    }
    const double restored_delta = snapshot_difference(snapshot_path, restored_path);
    printf("[swap_snapshot_test] restored machine vs save point: %.4f of "
           "snapshot bytes (drift was %.4f)\n", restored_delta, drift_delta);
    if (restored_delta > STATE_RESTORE_TOLERANCE ||
        restored_delta > drift_delta / 10.0) {
        return fail("the restored machine's state is not the save point's -- "
                    "the snapshot did not restore the machine state");
    }

    /* --- 4. hot-swap to title B ----------------------------------------- */
    printf("[swap_snapshot_test] swapping to title B: %s\n", paths[1]);
    if (vice_core_start(types[1], paths[1], NULL) != 0) {
        return fail("vice_core_start(B) returned nonzero (swap not queued)");
    }
    sleep_ms(25000);
    if (!capture(&g_b)) return fail("no framebuffer after title B");
    dump_ppm(&g_b, "title_b");

    const double swap_diff = frame_difference(&g_a, &g_b);
    printf("[swap_snapshot_test] A vs B frame difference: %.4f\n", swap_diff);
    if (swap_diff < RESTORE_TOLERANCE) {
        return fail("frame barely changed after swap -- title B did not load");
    }

    /* --- 5. cross-session restore: back to A while B is running --------- *
     *
     * This is the app's real Resume flow. It is a stricter test than step 3
     * because title B's swap detached A's media, so everything the restored
     * machine needs has to have come out of the snapshot file itself. */
    const int32_t cross_result = vice_core_load_snapshot(snapshot_path);
    printf("[swap_snapshot_test] cross-session load_snapshot -> %d\n", cross_result);
    if (cross_result != 0) {
        return fail("restoring title A's snapshot while title B was running "
                    "failed -- this is exactly what the Resume list does");
    }
    sleep_ms(300);
    if (!capture(&g_restored_cross)) return fail("no framebuffer after cross restore");
    dump_ppm(&g_restored_cross, "restored_cross");

    if (still_screen) {
        const double cross_vs_save = frame_difference(&g_saved, &g_restored_cross);
        printf("[swap_snapshot_test] cross-session restored vs title A save "
               "point: %.4f\n", cross_vs_save);
        if (cross_vs_save > RESTORE_TOLERANCE) {
            return fail("restoring title A's snapshot after playing title B did "
                        "not bring title A back -- Resume would lie to the user");
        }
    }

    if (vice_core_save_snapshot(restored_path) != 0) {
        return fail("could not save the cross-restored-point snapshot");
    }
    const double cross_delta = snapshot_difference(snapshot_path, restored_path);
    printf("[swap_snapshot_test] cross-session restored machine vs title A save "
           "point: %.4f of snapshot bytes\n", cross_delta);
    if (cross_delta > STATE_RESTORE_TOLERANCE ||
        cross_delta > drift_delta / 10.0) {
        return fail("restoring title A's snapshot after playing title B did "
                    "not bring title A's machine back -- Resume would lie to "
                    "the user");
    }

    printf("[swap_snapshot_test] PASS\n");
    return 0;
}
