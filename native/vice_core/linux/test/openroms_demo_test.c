/*
 * openroms_demo_test.c - does the bundled demo run with NO Commodore ROMs?
 *
 * The app's claim to a first-run user (and to an App Store reviewer) is that
 * it demonstrates itself with nothing supplied: the Open ROMs boot a real
 * C64, and the demo .prg the user picks out of the library runs on it.
 *
 * Both halves of that need proving together, because the interesting failure
 * is in the seam. A .prg is not read by the 1541 -- VICE injects it into
 * memory and pokes BASIC's pointers -- but the autostart path still leans on
 * the KERNAL, and the Open ROMs are a reimplementation that does not
 * implement every routine. "It boots" would not have told us this works.
 *
 * So: point the core at a directory holding ONLY the Open ROMs (no DRIVES,
 * no 1541 image at all), autostart the .prg, and write the framebuffer out
 * as a PPM to be looked at. Also counts non-background pixels, so a black
 * screen fails loudly rather than producing a file nobody opens.
 *
 * usage: openroms_demo_test <rom_dir> <demo.prg> <out.ppm> [inject]
 *
 * Pass "inject" to select RAM-injection autostart, which is what the app
 * does when the Open ROMs are the installed set. Without it the virtual
 * filesystem path is used, which is what real ROMs get.
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
    if (argc < 4) {
        fprintf(stderr, "usage: %s <rom_dir> <demo.prg> <out.ppm>\n", argv[0]);
        return 2;
    }
    const char *rom_dir = argv[1];
    const char *prg = argv[2];
    const char *out_path = argv[3];

    const int inject = (argc > 4 && strcmp(argv[4], "inject") == 0);
    vice_core_init(rom_dir);
    vice_core_set_prg_inject(inject);
    if (vice_core_start(VICE_MEDIA_PRG, prg, NULL) != 0) {
        fprintf(stderr, "FAIL: vice_core_start(PRG) returned nonzero\n");
        return 1;
    }

    int running = 0;
    for (int i = 0; i < 150; i++) {
        if (vice_core_is_running()) { running = 1; break; }
        sleep_ms(100);
    }
    if (!running) {
        fprintf(stderr, "FAIL: core never started\n");
        return 1;
    }

    /* Long enough for the ROM banner, the autostart LOAD/RUN, and the
     * program's own output to have been drawn. */
    sleep_ms(12000);

    int32_t w = 0, h = 0;
    const uint32_t *fb = vice_core_get_framebuffer(&w, &h);
    if (fb == NULL || w <= 0 || h <= 0) {
        fprintf(stderr, "FAIL: no framebuffer (%dx%d)\n", w, h);
        return 1;
    }

    /* The demo's first line blacks both border and background, so "lit"
     * pixels are its text. A screen with almost none of them means the
     * program did not run, whatever the ROM banner said. */
    long lit = 0;
    for (long i = 0; i < (long)w * h; i++) {
        uint32_t p = fb[i];
        int r = (p >> 16) & 0xff, g = (p >> 8) & 0xff, b = p & 0xff;
        if (r + g + b > 200) lit++;
    }

    FILE *f = fopen(out_path, "wb");
    if (f == NULL) { perror("fopen"); return 1; }
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (long i = 0; i < (long)w * h; i++) {
        uint32_t p = fb[i];
        unsigned char rgb[3] = {(p >> 16) & 0xff, (p >> 8) & 0xff, p & 0xff};
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);

    printf("frame %dx%d, %ld lit pixels -> %s\n", w, h, lit, out_path);
    vice_core_stop();
    if (lit < 500) {
        fprintf(stderr, "FAIL: screen is essentially blank; the demo did not run\n");
        return 1;
    }
    printf("PASS\n");
    return 0;
}
