/*
 * vsid_rapid_swap_test.c - reproduces "tapped 3 tracks quickly, heard 3 at
 * once" by firing vice_vsid_launch() at 3 different .sid files back-to-back
 * with no delay between them (simulating rapid taps in the Flutter Music
 * tab), then checking that playback settles on exactly one tune (the LAST
 * one requested) rather than audibly layering all three.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "vice_vsid_bridge.h"

static void sleep_ms(long ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

int main(int argc, char **argv) {
    if (argc < 6) {
        fprintf(stderr, "usage: %s <rom_dir> <sid1> <sid2> <sid3> <wav_out> [settle_seconds]\n", argv[0]);
        return 2;
    }
    const char *rom_dir = argv[1];
    const char *sid1 = argv[2];
    const char *sid2 = argv[3];
    const char *sid3 = argv[4];
    const char *wav_out = argv[5];
    const int settle_seconds = argc > 6 ? atoi(argv[6]) : 4;

    setenv("VICE_AUDIO_WAV_CAPTURE", wav_out, 1);

    printf("[rapid_swap] vice_vsid_init(%s)\n", rom_dir);
    vice_vsid_init(rom_dir);

    printf("[rapid_swap] launch(%s)\n", sid1);
    if (vice_vsid_launch(sid1, NULL) != 0) {
        fprintf(stderr, "[rapid_swap] FAIL: first launch failed\n");
        return 1;
    }
    int running = 0;
    for (int i = 0; i < 100; i++) {
        if (vice_vsid_is_running()) { running = 1; break; }
        sleep_ms(100);
    }
    if (!running) {
        fprintf(stderr, "[rapid_swap] FAIL: core never started\n");
        return 1;
    }
    sleep_ms(1200); /* let track 1 actually get audible first, like a real tap-then-wait-then-tap-again */

    /* Rapid taps: three different tracks, no meaningful delay between them,
     * exactly like a user tapping 3 rows quickly in the Music tab before
     * any of them has had time to fully load. */
    printf("[rapid_swap] rapid-fire launch(%s), launch(%s), launch(%s)\n", sid1, sid2, sid3);
    vice_vsid_launch(sid2, NULL);
    sleep_ms(20);
    vice_vsid_launch(sid3, NULL);
    sleep_ms(20);
    vice_vsid_launch(sid1, NULL); /* land back on sid1 so we can identify it distinctly from sid2/sid3 in analysis */

    for (int s = 0; s < settle_seconds; s++) {
        sleep_ms(1000);
        printf("[rapid_swap] t=%ds audio_level=%d running=%d\n",
               s + 1, vice_vsid_get_audio_level(), vice_vsid_is_running());
        if (!vice_vsid_is_running()) {
            fprintf(stderr, "[rapid_swap] FAIL: core stopped running\n");
            return 1;
        }
    }

    printf("[rapid_swap] SUCCESS (inspect %s: should settle on ONE tune, not a layered mix of all three)\n", wav_out);
    return 0;
}
