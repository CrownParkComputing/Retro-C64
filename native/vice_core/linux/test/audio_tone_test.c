/*
 * audio_tone_test.c - Milestone-2 part-1 verification for the real ALSA
 * sound backend (audio_backend.c).
 *
 * Boots the x64sc core with no media, waits for BASIC to be ready, injects
 * the classic C64 SID register-poke tone test via VICE's own keyboard
 * buffer (kbdbuf_feed, exported by libvicecore.so -- same mechanism VICE
 * uses for -keybuf/autotyping), lets it play for several seconds while
 * audio_backend.c mirrors the PCM stream to a WAV file (VICE_AUDIO_WAV_CAPTURE
 * env var, set below), then leaves the WAV on disk for offline RMS/peak
 * analysis (see test/analyze_wav.py).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "vice_bridge.h"

/* Exported by libvicecore.so (VICE's src/kbdbuf.c, compiled into the base
 * object list); feeds a string into the C64's own kernal keyboard buffer,
 * same as VICE's -keybuf. */
extern int kbdbuf_feed(const char *s);

static void sleep_ms(long ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <rom_dir> <wav_out_path> [capture_seconds]\n", argv[0]);
        return 2;
    }
    const char *rom_dir = argv[1];
    const char *wav_out = argv[2];
    const int capture_seconds = argc > 3 ? atoi(argv[3]) : 6;

    /* audio_backend_init() (called when VICE opens the "alsa" sound device)
     * reads this at core-start time. */
    setenv("VICE_AUDIO_WAV_CAPTURE", wav_out, 1);

    printf("[audio_tone_test] vice_core_init(%s)\n", rom_dir);
    vice_core_init(rom_dir);

    printf("[audio_tone_test] vice_core_start(no media)\n");
    if (vice_core_start(VICE_MEDIA_NONE, NULL, NULL) != 0) {
        fprintf(stderr, "[audio_tone_test] FAIL: vice_core_start returned nonzero\n");
        return 1;
    }

    int running = 0;
    for (int i = 0; i < 100; i++) {
        if (vice_core_is_running()) { running = 1; break; }
        sleep_ms(100);
    }
    if (!running) {
        fprintf(stderr, "[audio_tone_test] FAIL: core never reported running within 10s\n");
        return 1;
    }
    printf("[audio_tone_test] core running, waiting for BASIC boot text / READY prompt\n");

    /* Let the KERNAL/BASIC boot sequence finish (ROM banner + READY.) before
     * queuing keystrokes -- kbdbuf_feed queues into the same buffer BASIC's
     * own input routine drains, so feeding too early just means the boot
     * banner's own (empty) input eats nothing extra, but we still want the
     * screen settled for a realistic "typed at the prompt" scenario. */
    sleep_ms(2500);

    const char *program =
        "POKE54296,15:POKE54277,0:POKE54278,240:POKE54273,25:POKE54272,17:POKE54276,33\r";
    printf("[audio_tone_test] feeding keystrokes: %s", program);
    if (kbdbuf_feed(program) != 0) {
        fprintf(stderr, "[audio_tone_test] WARN: kbdbuf_feed reported an error (buffer full?)\n");
    }

    /* Give the kernal a moment to drain the typeahead buffer and execute the
     * POKEs, then let the SID free-run and capture. */
    sleep_ms(1500);
    printf("[audio_tone_test] capturing audio for %d seconds (audio_level=%d)\n",
           capture_seconds, vice_core_get_audio_level());
    for (int s = 0; s < capture_seconds; s++) {
        sleep_ms(1000);
        printf("[audio_tone_test]   t=%ds audio_level=%d fps=%d\n",
               s + 1, vice_core_get_audio_level(), vice_core_get_fps());
        if (!vice_core_is_running()) {
            fprintf(stderr, "[audio_tone_test] FAIL: core stopped running during capture\n");
            return 1;
        }
    }

    vice_core_stop();
    /* audio_backend.c patches the WAV header after every chunk, so the file
     * on disk is already valid; no explicit flush/close call needed. */
    sleep_ms(300);

    printf("[audio_tone_test] SUCCESS: wav written to %s\n", wav_out);
    return 0;
}
