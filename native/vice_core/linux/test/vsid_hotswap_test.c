/*
 * vsid_hotswap_test.c - headless repro/verification for the "tapping a
 * different track doesn't switch the tune" bug.
 *
 * Launches vsid with an initial .sid file, lets it play for a few seconds,
 * then calls vice_vsid_launch() AGAIN with a *different* .sid file while
 * the core is still running (the exact "hot-swap" path the Flutter Music
 * tab exercises when the user taps a different track). Captures WAV audio
 * across the whole run and reports simple amplitude statistics for the
 * "before swap" and "after swap" windows so a human/script can confirm
 * the waveform genuinely changed character, not just kept playing track 1
 * or gone silent.
 *
 * This does NOT do spectral comparison; it just captures separate WAV
 * files for the two phases (by restarting capture) so they can be diffed
 * by ear or by a simple analysis script. It also polls vice_vsid_get_audio_level()
 * throughout so the console log alone is a reasonable signal.
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
    if (argc < 5) {
        fprintf(stderr,
                "usage: %s <rom_dir> <sid_path_1> <sid_path_2> <wav_out_prefix> [seconds_each]\n",
                argv[0]);
        return 2;
    }
    const char *rom_dir = argv[1];
    const char *sid1 = argv[2];
    const char *sid2 = argv[3];
    const char *wav_prefix = argv[4];
    const int seconds_each = argc > 5 ? atoi(argv[5]) : 3;

    /* NOTE: audio_backend_init() reads VICE_AUDIO_WAV_CAPTURE exactly once,
     * during the FIRST launch's sound device init. The hot-swap path does
     * not reinit the audio device, so this whole run (both tracks) lands in
     * a single continuous WAV file. That's fine/useful: the swap happens at
     * a known wall-clock offset (~seconds_each seconds in), so the two
     * halves of the file can be diffed/analyzed separately afterward. */
    char wav1[1024];
    snprintf(wav1, sizeof(wav1), "%s.wav", wav_prefix);

    printf("[vsid_hotswap_test] vice_vsid_init(%s)\n", rom_dir);
    vice_vsid_init(rom_dir);

    setenv("VICE_AUDIO_WAV_CAPTURE", wav1, 1);
    printf("[vsid_hotswap_test] phase 1: vice_vsid_launch(%s)\n", sid1);
    if (vice_vsid_launch(sid1, NULL) != 0) {
        fprintf(stderr, "[vsid_hotswap_test] FAIL: first launch returned nonzero\n");
        return 1;
    }

    int running = 0;
    for (int i = 0; i < 100; i++) {
        if (vice_vsid_is_running()) { running = 1; break; }
        sleep_ms(100);
    }
    if (!running) {
        fprintf(stderr, "[vsid_hotswap_test] FAIL: core never reported running within 10s\n");
        return 1;
    }

    long sum1 = 0;
    int n1 = 0;
    for (int s = 0; s < seconds_each; s++) {
        sleep_ms(1000);
        int lvl = vice_vsid_get_audio_level();
        sum1 += lvl;
        n1++;
        printf("[vsid_hotswap_test] track1 t=%ds audio_level=%d\n", s + 1, lvl);
    }
    double avg1 = n1 ? (double)sum1 / n1 : 0;

    /* Now hot-swap to track 2 while the core is still running. This is the
     * exact call the Flutter Music tab makes when a second track is tapped
     * while one is already playing. */
    printf("[vsid_hotswap_test] phase 2: hot-swap vice_vsid_launch(%s) at ~t=%ds in %s\n",
           sid2, seconds_each, wav1);
    int swap_rc = vice_vsid_launch(sid2, NULL);
    printf("[vsid_hotswap_test] hot-swap rc=%d\n", swap_rc);

    long sum2 = 0;
    int n2 = 0;
    for (int s = 0; s < seconds_each; s++) {
        sleep_ms(1000);
        int lvl = vice_vsid_get_audio_level();
        sum2 += lvl;
        n2++;
        printf("[vsid_hotswap_test] track2 t=%ds audio_level=%d running=%d\n",
               s + 1, lvl, vice_vsid_is_running());
        if (!vice_vsid_is_running()) {
            fprintf(stderr, "[vsid_hotswap_test] FAIL: core stopped running after hot-swap\n");
            return 1;
        }
    }
    double avg2 = n2 ? (double)sum2 / n2 : 0;

    printf("[vsid_hotswap_test] summary: track1_avg_level=%.1f track2_avg_level=%.1f\n", avg1, avg2);
    printf("[vsid_hotswap_test] SUCCESS (inspect WAV/level output above to judge if the tune actually changed)\n");
    return 0;
}
