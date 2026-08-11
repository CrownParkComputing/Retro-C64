/*
 * joystick_port_test.c - Proves vice_core_joystick()'s port argument really
 * decides which of the C64's two joystick ports receives the input.
 *
 * The method is the only one that actually demonstrates it end to end: take
 * a title sitting on a still "press fire to start" screen, hold FIRE on the
 * WRONG port and show the screen does not change, then hold FIRE on the
 * RIGHT port and show it does. A test that merely called the function with
 * each port number and checked the return value would pass even if the port
 * argument were ignored entirely, which is exactly the bug worth catching.
 *
 * The caller says which port the title is expected to read, so the test
 * works for a port-1 game just as well as a port-2 one.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "vice_bridge.h"

/* VICE's own read-back of a joyport's current value (src/joyport/joystick.h).
 * Used for the routing assertions below: it is the exact state the emulated
 * machine reads, so checking it proves the port argument lands where it
 * should without depending on any particular game reacting. */
extern uint16_t get_joystick_value(int index);

#define VICE_JOY_FIRE1 0x10
#define VICE_JOY_UP 0x01

/* JOYPORT_1 / JOYPORT_2 as get_joystick_value() indexes them. */
#define JOYPORT_INDEX_1 0
#define JOYPORT_INDEX_2 1

static void sleep_ms(long ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

#define MAX_PIXELS (1024 * 1024)

typedef struct {
    int width;
    int height;
    uint32_t pixels[MAX_PIXELS];
} frame_copy_t;

static frame_copy_t g_idle, g_wrong, g_right;

static int capture(frame_copy_t *out) {
    int32_t w = 0, h = 0;
    const uint32_t *fb = vice_core_get_framebuffer(&w, &h);
    if (fb == NULL || w <= 0 || h <= 0 || (size_t)w * (size_t)h > MAX_PIXELS) return 0;
    out->width = w;
    out->height = h;
    memcpy(out->pixels, fb, (size_t)w * (size_t)h * sizeof(uint32_t));
    return 1;
}

static double frame_difference(const frame_copy_t *a, const frame_copy_t *b) {
    if (a->width != b->width || a->height != b->height) return 1.0;
    const size_t n = (size_t)a->width * (size_t)a->height;
    size_t differing = 0;
    for (size_t i = 0; i < n; i++) {
        if (a->pixels[i] != b->pixels[i]) differing++;
    }
    return n == 0 ? 1.0 : (double)differing / (double)n;
}

static void dump_ppm(const frame_copy_t *f, const char *name) {
    char path[512];
    snprintf(path, sizeof(path), "/tmp/vice_port_test_%s.ppm", name);
    FILE *fp = fopen(path, "wb");
    if (fp == NULL) return;
    fprintf(fp, "P6\n%d %d\n255\n", f->width, f->height);
    const size_t n = (size_t)f->width * (size_t)f->height;
    for (size_t i = 0; i < n; i++) {
        const uint32_t px = f->pixels[i];
        const uint8_t rgb[3] = {(uint8_t)(px & 0xff), (uint8_t)((px >> 8) & 0xff),
                                (uint8_t)((px >> 16) & 0xff)};
        fwrite(rgb, 1, 3, fp);
    }
    fclose(fp);
    printf("[joystick_port_test] wrote %s\n", path);
}

/* Holds FIRE on `port` for a while, releases it, and reports how much the
 * picture changed compared with `before`. */
static double press_fire_on(int port, const frame_copy_t *before, frame_copy_t *after) {
    printf("[joystick_port_test] holding FIRE on port %d\n", port);
    for (int i = 0; i < 6; i++) {
        vice_core_joystick(port, VICE_JOY_FIRE1);
        sleep_ms(250);
        vice_core_joystick(port, 0);
        sleep_ms(250);
    }
    sleep_ms(2500);
    if (!capture(after)) return -1.0;
    return frame_difference(before, after);
}

static int fail(const char *msg) {
    fprintf(stderr, "[joystick_port_test] FAIL: %s\n", msg);
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr,
                "usage: %s <rom_dir> <title> [expected_port] [boot_seconds]\n"
                "  title is either a .vsf snapshot to restore, or\n"
                "  \"<type>:<path>\" (prg|disk|tape) to boot from scratch.\n"
                "  Either way it must end up on a still 'press fire' screen.\n"
                "  expected_port defaults to 2, boot_seconds to 90.\n",
                argv[0]);
        return 2;
    }
    const char *rom_dir = argv[1];
    const char *title = argv[2];
    const int expected_port = argc > 3 ? atoi(argv[3]) : 2;
    const int boot_seconds = argc > 4 ? atoi(argv[4]) : 90;
    /* The screen-based end-to-end phase only means anything for a title
     * that is genuinely parked waiting for FIRE. Most are not: cracktros
     * and trainer prompts advance on their own timer (indistinguishable
     * from a reaction), and plenty of title screens want a function key
     * instead. So it is opt-in, and the deterministic routing assertions
     * above are what this test always checks. */
    const int check_screen = argc > 5 && strcmp(argv[5], "fire-starts-game") == 0;
    const int other_port = expected_port == 1 ? 2 : 1;

    const char *colon = strchr(title, ':');
    const int from_snapshot = (colon == NULL);

    vice_core_init(rom_dir);

    if (from_snapshot) {
        if (vice_core_start(VICE_MEDIA_NONE, NULL, NULL) != 0) {
            return fail("vice_core_start failed");
        }
    } else {
        int media_type;
        if (strncmp(title, "prg", 3) == 0) media_type = VICE_MEDIA_PRG;
        else if (strncmp(title, "disk", 4) == 0) media_type = VICE_MEDIA_DISK;
        else if (strncmp(title, "tape", 4) == 0) media_type = VICE_MEDIA_TAPE;
        else return fail("unknown media type in title spec");
        if (vice_core_start(media_type, colon + 1, NULL) != 0) {
            return fail("vice_core_start failed");
        }
    }

    int running = 0;
    for (int i = 0; i < 150; i++) {
        if (vice_core_is_running()) { running = 1; break; }
        sleep_ms(100);
    }
    if (!running) return fail("core never reported running");

    if (from_snapshot) {
        sleep_ms(3000);
        /* Restoring a snapshot puts us straight on the title screen without
         * waiting out a disk load. */
        if (vice_core_load_snapshot(title) != 0) {
            return fail("vice_core_load_snapshot failed");
        }
        sleep_ms(3000);
    } else {
        printf("[joystick_port_test] booting for %ds...\n", boot_seconds);
        sleep_ms((long)boot_seconds * 1000);
    }
    if (!capture(&g_idle)) return fail("no framebuffer after restore");
    dump_ppm(&g_idle, "idle");

    /* ---------------------------------------------------------------- *
     * Routing assertions.                                              *
     *                                                                  *
     * These read back the value VICE itself holds for each joyport, so *
     * they prove the port argument selects the real port regardless of *
     * whether any particular title happens to react. The screen-based  *
     * check further down is the end-to-end complement to this, but it  *
     * needs a title parked on a genuine "press fire" screen -- plenty  *
     * of C64 titles sit on cracktros and trainer prompts that advance  *
     * on their own timer, which no frame comparison can tell apart     *
     * from a reaction.                                                 *
     * ---------------------------------------------------------------- */
    for (int port = 1; port <= 2; port++) {
        const int other = port == 1 ? 2 : 1;
        const int this_index = port == 1 ? JOYPORT_INDEX_1 : JOYPORT_INDEX_2;
        const int other_index = port == 1 ? JOYPORT_INDEX_2 : JOYPORT_INDEX_1;

        vice_core_joystick(1, 0);
        vice_core_joystick(2, 0);
        vice_core_joystick(port, VICE_JOY_FIRE1 | VICE_JOY_UP);
        sleep_ms(120);

        const uint16_t on_this = get_joystick_value(this_index);
        const uint16_t on_other = get_joystick_value(other_index);
        printf("[joystick_port_test] set port %d -> port%d=0x%04x port%d=0x%04x\n",
               port, port, on_this, other, on_other);

        if (on_this == 0) {
            return fail("the port that was set reads back as idle -- the input "
                        "never reached it");
        }
        if (on_other != 0) {
            return fail("the OTHER port also changed -- input is not being "
                        "confined to the selected port");
        }
        vice_core_joystick(port, 0);
        sleep_ms(120);
        if (get_joystick_value(this_index) != 0) {
            return fail("releasing the joystick left the port latched");
        }
    }
    printf("[joystick_port_test] routing assertions PASSED for both ports\n");

    if (!check_screen) {
        printf("[joystick_port_test] PASS (routing assertions; screen phase "
               "not requested -- pass \"fire-starts-game\" as the 5th argument "
               "for a title that waits on FIRE)\n");
        return 0;
    }

    /* Measure how much the screen moves on its own. Every threshold below
     * is expressed relative to this, because few C64 title screens are
     * perfectly static -- a flashing "PRESS FIRE" prompt or a colour cycle
     * puts a percent or two of the picture in motion permanently, and a
     * fixed threshold would either reject those titles or drown in them. */
    static frame_copy_t settle;
    sleep_ms(1200);
    if (!capture(&settle)) return fail("no framebuffer for stillness check");
    const double idle_motion = frame_difference(&g_idle, &settle);
    printf("[joystick_port_test] idle motion: %.4f\n", idle_motion);
    if (idle_motion > 0.15) {
        return fail("this screen animates far too much for a fire press to be "
                    "distinguishable; use a title parked on a quiet screen");
    }
    /* A press "did nothing" if it moved no more than the screen moves by
     * itself; it "did something" if it moved several times more than that. */
    const double noise_ceiling = idle_motion * 2.0 + 0.01;
    const double action_floor = idle_motion * 4.0 + 0.05;
    printf("[joystick_port_test] noise ceiling %.4f, action floor %.4f\n",
           noise_ceiling, action_floor);
    capture(&g_idle);

    /* --- wrong port: nothing should happen ----------------------------- */
    const double wrong_diff = press_fire_on(other_port, &g_idle, &g_wrong);
    dump_ppm(&g_wrong, "wrong_port");
    printf("[joystick_port_test] port %d (not the game's) changed %.4f of the picture\n",
           other_port, wrong_diff);
    if (wrong_diff > noise_ceiling) {
        return fail("firing on the port the game does NOT read still changed the "
                    "screen -- the port argument is not being honoured");
    }

    /* --- right port: the game must react ------------------------------- */
    const double right_diff = press_fire_on(expected_port, &g_idle, &g_right);
    dump_ppm(&g_right, "right_port");
    printf("[joystick_port_test] port %d (the game's) changed %.4f of the picture\n",
           expected_port, right_diff);
    if (right_diff < action_floor) {
        return fail("firing on the port the game DOES read changed nothing -- "
                    "either the port routing is broken or this snapshot is not "
                    "on a 'press fire' screen");
    }

    printf("[joystick_port_test] PASS (port %d ignored, port %d acted on)\n",
           other_port, expected_port);
    return 0;
}
