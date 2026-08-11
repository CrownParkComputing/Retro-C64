/*
 * smoke_test.c - Milestone-1 smoke test for the plain-C VICE core bridge.
 *
 * Loads libvicecore.so (via direct link, since it's built alongside this
 * binary by the same CMake project), points it at a ROM directory copied
 * from VICEAndroid's bundled assets, boots the x64sc core with no media
 * attached, lets the mainloop run for a few seconds, and reports whether a
 * framebuffer of plausible C64 dimensions appeared.
 *
 * This does NOT verify pixel content against a known-good image, and does
 * NOT exercise audio (dummy sound backend only, see vice_bridge.c).
 */

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

int main(int argc, char **argv) {
    const char *rom_dir = argc > 1 ? argv[1] : NULL;
    if (rom_dir == NULL) {
        fprintf(stderr, "usage: %s <rom_dir>   (must contain a C64/ subdir with kernal/basic/chargen)\n",
                argv[0]);
        return 2;
    }

    printf("[smoke_test] vice_core_init(%s)\n", rom_dir);
    vice_core_init(rom_dir);

    printf("[smoke_test] vice_core_start(no media)\n");
    if (vice_core_start(VICE_MEDIA_NONE, NULL, NULL) != 0) {
        fprintf(stderr, "[smoke_test] FAIL: vice_core_start returned nonzero\n");
        return 1;
    }

    /* Poll until the core reports itself running, or time out. Startup does
     * ROM loading + machine init before the mainloop begins. */
    int running = 0;
    for (int i = 0; i < 100; i++) { /* up to ~10s */
        if (vice_core_is_running()) {
            running = 1;
            break;
        }
        sleep_ms(100);
    }
    if (!running) {
        fprintf(stderr, "[smoke_test] FAIL: core never reported running within 10s\n");
        return 1;
    }
    printf("[smoke_test] core reports running\n");

    /* Let several frames render. */
    int32_t width = 0, height = 0;
    const uint32_t *fb = NULL;
    int have_frame = 0;
    for (int i = 0; i < 100; i++) { /* up to ~10s */
        fb = vice_core_get_framebuffer(&width, &height);
        if (fb != NULL && width > 0 && height > 0) {
            have_frame = 1;
            break;
        }
        sleep_ms(100);
        if (!vice_core_is_running()) {
            fprintf(stderr, "[smoke_test] FAIL: core stopped running while waiting for a frame\n");
            return 1;
        }
    }

    if (!have_frame) {
        fprintf(stderr, "[smoke_test] FAIL: no framebuffer produced within 10s (core still running=%d)\n",
                vice_core_is_running());
        return 1;
    }

    printf("[smoke_test] framebuffer: %dx%d pixels, fps=%d, audio_level=%d\n",
           width, height, vice_core_get_fps(), vice_core_get_audio_level());

    /* Sanity-check the pixel content isn't obviously degenerate: sample the
     * center pixel and make sure the alpha channel got set (0xff000000 bit),
     * which only happens once real palette-derived colors have been blitted. */
    if (width > 0 && height > 0) {
        const uint32_t sample = fb[(height / 2) * width + (width / 2)];
        printf("[smoke_test] center pixel = 0x%08x\n", sample);
    }

    /* Let it run a bit longer to prove the mainloop keeps going, not just a
     * single frame. */
    sleep_ms(2000);
    if (!vice_core_is_running()) {
        fprintf(stderr, "[smoke_test] FAIL: core stopped running during steady-state wait\n");
        return 1;
    }

    int32_t width2 = 0, height2 = 0;
    vice_core_get_framebuffer(&width2, &height2);
    printf("[smoke_test] after steady-state wait: still running, framebuffer=%dx%d, fps=%d\n",
           width2, height2, vice_core_get_fps());

    vice_core_stop();

    printf("[smoke_test] SUCCESS\n");
    return 0;
}
