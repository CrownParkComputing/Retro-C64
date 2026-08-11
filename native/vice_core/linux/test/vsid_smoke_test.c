/*
 * vsid_smoke_test.c - Milestone-2 part-2 smoke test for the plain-C vsid
 * bridge (vice_vsid_bridge.c / libvicecore_vsid.so).
 *
 * Boots the vsid core, optionally autostarting a .sid file, and confirms
 * the core reaches a running state without crashing. If a WAV capture path
 * is given, captures a few seconds of PCM the same way audio_tone_test.c
 * does for the game core, via the same shared ALSA/WAV audio_backend.c.
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
    if (argc < 2) {
        fprintf(stderr,
                "usage: %s <rom_dir> [sid_path] [wav_out_path] [capture_seconds]\n"
                "  sid_path may be omitted to verify clean init/start with no tune.\n",
                argv[0]);
        return 2;
    }
    const char *rom_dir = argv[1];
    const char *sid_path = argc > 2 && argv[2][0] != '\0' ? argv[2] : NULL;
    const char *wav_out = argc > 3 && argv[3][0] != '\0' ? argv[3] : NULL;
    const int capture_seconds = argc > 4 ? atoi(argv[4]) : 5;

    if (wav_out != NULL) {
        setenv("VICE_AUDIO_WAV_CAPTURE", wav_out, 1);
    }

    printf("[vsid_smoke_test] vice_vsid_init(%s)\n", rom_dir);
    vice_vsid_init(rom_dir);

    printf("[vsid_smoke_test] vice_vsid_launch(%s)\n", sid_path ? sid_path : "(none)");
    if (vice_vsid_launch(sid_path, NULL) != 0) {
        fprintf(stderr, "[vsid_smoke_test] FAIL: vice_vsid_launch returned nonzero\n");
        return 1;
    }

    int running = 0;
    for (int i = 0; i < 100; i++) { /* up to ~10s */
        if (vice_vsid_is_running()) { running = 1; break; }
        sleep_ms(100);
    }
    if (!running) {
        fprintf(stderr, "[vsid_smoke_test] FAIL: vsid core never reported running within 10s\n");
        return 1;
    }
    printf("[vsid_smoke_test] vsid core running, audio_level=%d\n", vice_vsid_get_audio_level());

    if (sid_path != NULL) {
        printf("[vsid_smoke_test] capturing/observing for %d seconds\n", capture_seconds);
        for (int s = 0; s < capture_seconds; s++) {
            sleep_ms(1000);
            printf("[vsid_smoke_test]   t=%ds audio_level=%d running=%d\n",
                   s + 1, vice_vsid_get_audio_level(), vice_vsid_is_running());
            if (!vice_vsid_is_running()) {
                fprintf(stderr, "[vsid_smoke_test] FAIL: vsid core stopped running during playback\n");
                return 1;
            }
        }
    } else {
        /* No tune given: just prove a few seconds of idle vsid lifecycle
         * doesn't crash (the "clean error, no crash" case from the task
         * brief, mirroring vice_bridge.c's missing-ROM double-free fix). */
        sleep_ms(1500);
        if (!vice_vsid_is_running()) {
            fprintf(stderr, "[vsid_smoke_test] FAIL: vsid core stopped running while idle\n");
            return 1;
        }
    }

    sleep_ms(300);
    printf("[vsid_smoke_test] SUCCESS\n");
    return 0;
}
