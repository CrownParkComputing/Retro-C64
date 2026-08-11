/*
 * sdl_viewer.c - SDL3 debug viewer for the plain-C VICE bridges.
 *
 * Two modes, selected by argv[1]:
 *
 *   core <rom_dir> [media_type media_path]
 *       Opens a visible window, dlopen()s libvicecore.so (never linked
 *       directly, see note below), boots the x64sc game core, blits its
 *       RGBA8888 framebuffer into an SDL texture every frame, and forwards
 *       keyboard input into the C64 keyboard matrix. Ctrl+F12 (or
 *       --dump-frame/-D on the command line) writes the current frame out
 *       as a .ppm so the result can be inspected without a screenshot tool.
 *
 *   vsid <rom_dir> <sid_path> [wav_out seconds]
 *       No window (vsid has no video canvas). dlopen()s
 *       libvicecore_vsid.so, boots the vsid machine, plays the given
 *       .sid/.psid file, and reports the audio peak level over time. If
 *       wav_out is given it also captures PCM via the shared ALSA/WAV
 *       audio_backend (VICE_AUDIO_WAV_CAPTURE), same mechanism as
 *       audio_tone_test.c / vsid_smoke_test.c, so the result can be
 *       verified offline (file size, non-silence) without live audio
 *       hardware.
 *
 * Why dlopen and not direct linking: libvicecore.so and libvicecore_vsid.so
 * are each a *complete* static link of the shared VICE base objects
 * (machine.c, keyboard.c, sound.c, ...), so both .so files export the same
 * global symbol names (machine_trigger_reset, keyboard_set_keyarr_any, ...)
 * with different definitions (c64sc vs vsid machine tables). Linking both
 * into one executable at build time would collide at link time; loading
 * both into one process with plain dlopen() risks the dynamic linker
 * resolving one library's internal calls into the other's same-named
 * symbols. This viewer therefore never links either library and only ever
 * has ONE of the two loaded at a time per process invocation (core or
 * vsid), each via dlopen(RTLD_NOW | RTLD_LOCAL | RTLD_DEEPBIND) so its
 * internal symbol references prefer its own definitions first.
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <SDL3/SDL.h>

/* ------------------------------------------------------------------ */
/* Shared helpers                                                      */
/* ------------------------------------------------------------------ */

static void sleep_ms(long ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

/* Dump an RGBA8888 framebuffer to a plain .ppm (P6) file -- no external
 * screenshot tool or PNG library required, and trivially viewable/diffable. */
static bool dump_ppm(const char *path, const uint32_t *fb, int w, int h) {
    if (fb == NULL || w <= 0 || h <= 0) {
        fprintf(stderr, "[dump_ppm] no frame to dump\n");
        return false;
    }
    FILE *f = fopen(path, "wb");
    if (f == NULL) {
        fprintf(stderr, "[dump_ppm] fopen(%s) failed\n", path);
        return false;
    }
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            const uint32_t px = fb[y * w + x];
            const unsigned char rgb[3] = {
                (unsigned char)(px & 0xff),
                (unsigned char)((px >> 8) & 0xff),
                (unsigned char)((px >> 16) & 0xff)
            };
            fwrite(rgb, 1, 3, f);
        }
    }
    fclose(f);
    fprintf(stderr, "[dump_ppm] wrote %s (%dx%d)\n", path, w, h);
    return true;
}

/* ------------------------------------------------------------------ */
/* Game-core (libvicecore.so) mode                                     */
/* ------------------------------------------------------------------ */

typedef void (*fn_vice_core_init)(const char *);
typedef int32_t (*fn_vice_core_start)(int32_t, const char *, const char *);
typedef void (*fn_vice_core_stop)(void);
typedef int32_t (*fn_vice_core_is_running)(void);
typedef void (*fn_vice_core_set_paused)(int32_t);
typedef void (*fn_vice_core_key_event)(int32_t, int32_t);
typedef void (*fn_vice_core_matrix_key_event)(int32_t, int32_t, int32_t);
typedef void (*fn_vice_core_joystick)(int32_t, int32_t);
typedef int32_t (*fn_vice_core_attach_disk)(const char *);
typedef int32_t (*fn_vice_core_attach_tape)(const char *);
typedef const uint32_t *(*fn_vice_core_get_framebuffer)(int32_t *, int32_t *);
typedef int32_t (*fn_vice_core_get_audio_level)(void);
typedef int32_t (*fn_vice_core_get_fps)(void);

struct core_api {
    void *handle;
    fn_vice_core_init init;
    fn_vice_core_start start;
    fn_vice_core_stop stop;
    fn_vice_core_is_running is_running;
    fn_vice_core_set_paused set_paused;
    fn_vice_core_key_event key_event;
    fn_vice_core_matrix_key_event matrix_key_event;
    fn_vice_core_joystick joystick;
    fn_vice_core_attach_disk attach_disk;
    fn_vice_core_attach_tape attach_tape;
    fn_vice_core_get_framebuffer get_framebuffer;
    fn_vice_core_get_audio_level get_audio_level;
    fn_vice_core_get_fps get_fps;
};

#define LOAD_SYM(api, field, name)                                          \
    do {                                                                    \
        (api)->field = (typeof((api)->field))dlsym((api)->handle, name);    \
        if ((api)->field == NULL) {                                         \
            fprintf(stderr, "[viewer] dlsym(%s) failed: %s\n", name,        \
                    dlerror());                                             \
            return false;                                                  \
        }                                                                   \
    } while (0)

static bool core_api_load(struct core_api *api, const char *so_path) {
    memset(api, 0, sizeof(*api));
    api->handle = dlopen(so_path, RTLD_NOW | RTLD_LOCAL | RTLD_DEEPBIND);
    if (api->handle == NULL) {
        fprintf(stderr, "[viewer] dlopen(%s) failed: %s\n", so_path, dlerror());
        return false;
    }
    LOAD_SYM(api, init, "vice_core_init");
    LOAD_SYM(api, start, "vice_core_start");
    LOAD_SYM(api, stop, "vice_core_stop");
    LOAD_SYM(api, is_running, "vice_core_is_running");
    LOAD_SYM(api, set_paused, "vice_core_set_paused");
    LOAD_SYM(api, key_event, "vice_core_key_event");
    LOAD_SYM(api, matrix_key_event, "vice_core_matrix_key_event");
    LOAD_SYM(api, joystick, "vice_core_joystick");
    LOAD_SYM(api, attach_disk, "vice_core_attach_disk");
    LOAD_SYM(api, attach_tape, "vice_core_attach_tape");
    LOAD_SYM(api, get_framebuffer, "vice_core_get_framebuffer");
    LOAD_SYM(api, get_audio_level, "vice_core_get_audio_level");
    LOAD_SYM(api, get_fps, "vice_core_get_fps");
    return true;
}

/* SDL scancode -> C64 keyboard matrix (row, column). -1,-1 = unmapped.
 * Matrix layout is the standard positional C64 matrix (as used by VICE's
 * own SDL port keymaps), covering the keys needed to type BASIC / boot
 * text and to watch the screen react live. */
struct matrix_map { SDL_Scancode sc; int row, col; };
static const struct matrix_map kKeyMap[] = {
    {SDL_SCANCODE_1, 7, 0}, {SDL_SCANCODE_2, 7, 3}, {SDL_SCANCODE_3, 1, 0},
    {SDL_SCANCODE_4, 1, 3}, {SDL_SCANCODE_5, 2, 0}, {SDL_SCANCODE_6, 2, 3},
    {SDL_SCANCODE_7, 3, 0}, {SDL_SCANCODE_8, 3, 3}, {SDL_SCANCODE_9, 4, 0},
    {SDL_SCANCODE_0, 4, 3},
    {SDL_SCANCODE_Q, 7, 6}, {SDL_SCANCODE_W, 1, 1}, {SDL_SCANCODE_E, 1, 6},
    {SDL_SCANCODE_R, 2, 1}, {SDL_SCANCODE_T, 2, 6}, {SDL_SCANCODE_Y, 3, 1},
    {SDL_SCANCODE_U, 3, 6}, {SDL_SCANCODE_I, 4, 1}, {SDL_SCANCODE_O, 4, 6},
    {SDL_SCANCODE_P, 5, 1},
    {SDL_SCANCODE_A, 1, 2}, {SDL_SCANCODE_S, 1, 5}, {SDL_SCANCODE_D, 2, 2},
    {SDL_SCANCODE_F, 2, 5}, {SDL_SCANCODE_G, 3, 2}, {SDL_SCANCODE_H, 3, 5},
    {SDL_SCANCODE_J, 4, 2}, {SDL_SCANCODE_K, 4, 5}, {SDL_SCANCODE_L, 5, 2},
    {SDL_SCANCODE_Z, 1, 4}, {SDL_SCANCODE_X, 2, 7}, {SDL_SCANCODE_C, 2, 4},
    {SDL_SCANCODE_V, 3, 7}, {SDL_SCANCODE_B, 3, 4}, {SDL_SCANCODE_N, 4, 7},
    {SDL_SCANCODE_M, 4, 4},
    {SDL_SCANCODE_SPACE, 7, 4},
    {SDL_SCANCODE_RETURN, 0, 1},
    {SDL_SCANCODE_BACKSPACE, 0, 0}, /* INST/DEL */
    {SDL_SCANCODE_LEFT, 0, 2}, {SDL_SCANCODE_RIGHT, 0, 2},
    {SDL_SCANCODE_UP, 0, 7}, {SDL_SCANCODE_DOWN, 0, 7},
    {SDL_SCANCODE_LSHIFT, 1, 7}, {SDL_SCANCODE_RSHIFT, 6, 4},
    {SDL_SCANCODE_LCTRL, 7, 2}, {SDL_SCANCODE_ESCAPE, 7, 7}, /* RUN/STOP */
    {SDL_SCANCODE_HOME, 6, 3}, /* CLR/HOME */
    {SDL_SCANCODE_PERIOD, 5, 4}, {SDL_SCANCODE_COMMA, 5, 7},
    {SDL_SCANCODE_SLASH, 6, 7}, {SDL_SCANCODE_APOSTROPHE, 6, 2},
    {SDL_SCANCODE_SEMICOLON, 5, 5}, {SDL_SCANCODE_EQUALS, 6, 5},
    {SDL_SCANCODE_MINUS, 5, 0},
};
#define KEYMAP_LEN (sizeof(kKeyMap) / sizeof(kKeyMap[0]))

static bool matrix_lookup(SDL_Scancode sc, int *row, int *col) {
    for (size_t i = 0; i < KEYMAP_LEN; i++) {
        if (kKeyMap[i].sc == sc) {
            *row = kKeyMap[i].row;
            *col = kKeyMap[i].col;
            return true;
        }
    }
    return false;
}

static int run_core_mode(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr,
                "usage: %s core <so_path> <rom_dir> [media_type media_path] "
                "[--dump-frame path] [--dump-after-seconds N] [--run-seconds N] "
                "[--headless]\n",
                argv[0]);
        return 2;
    }
    const char *so_path = argv[2];
    const char *rom_dir = argc > 3 ? argv[3] : NULL;
    int32_t media_type = -1;
    const char *media_path = NULL;
    const char *dump_path = NULL;
    int dump_after_seconds = 4;
    int run_seconds = 0; /* 0 = run until window closed */
    bool headless = false;

    int i = 4;
    if (argc > i && argv[i][0] != '-') {
        if (strcmp(argv[i], "none") == 0) media_type = -1;
        else if (strcmp(argv[i], "prg") == 0) media_type = 0;
        else if (strcmp(argv[i], "disk") == 0) media_type = 1;
        else if (strcmp(argv[i], "tape") == 0) media_type = 2;
        i++;
        if (argc > i && argv[i][0] != '-') { media_path = argv[i]; i++; }
    }
    for (; i < argc; i++) {
        if ((strcmp(argv[i], "--dump-frame") == 0 || strcmp(argv[i], "-D") == 0) && i + 1 < argc) {
            dump_path = argv[++i];
        } else if (strcmp(argv[i], "--dump-after-seconds") == 0 && i + 1 < argc) {
            dump_after_seconds = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--run-seconds") == 0 && i + 1 < argc) {
            run_seconds = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--headless") == 0) {
            headless = true;
        }
    }

    if (rom_dir == NULL) {
        fprintf(stderr, "[viewer] missing rom_dir\n");
        return 2;
    }

    struct core_api api;
    if (!core_api_load(&api, so_path)) {
        return 1;
    }

    printf("[viewer] vice_core_init(%s)\n", rom_dir);
    api.init(rom_dir);

    printf("[viewer] vice_core_start(media_type=%d media=%s)\n", media_type,
           media_path ? media_path : "(none)");
    if (api.start(media_type, media_path, NULL) != 0) {
        fprintf(stderr, "[viewer] FAIL: vice_core_start returned nonzero\n");
        return 1;
    }

    for (int w = 0; w < 100 && !api.is_running(); w++) sleep_ms(100);
    if (!api.is_running()) {
        fprintf(stderr, "[viewer] FAIL: core never reported running\n");
        return 1;
    }
    printf("[viewer] core running\n");

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "[viewer] SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }
    fprintf(stderr, "[viewer] SDL video driver: %s\n", SDL_GetCurrentVideoDriver());

    SDL_Window *window = NULL;
    SDL_Renderer *renderer = NULL;
    SDL_Texture *texture = NULL;
    int tex_w = 0, tex_h = 0;

    if (!headless) {
        window = SDL_CreateWindow("VICE C64 viewer (SDL3)", 768, 576, 0);
        if (window == NULL) {
            fprintf(stderr, "[viewer] SDL_CreateWindow failed: %s\n", SDL_GetError());
            return 1;
        }
        renderer = SDL_CreateRenderer(window, NULL);
        if (renderer == NULL) {
            fprintf(stderr, "[viewer] SDL_CreateRenderer failed: %s\n", SDL_GetError());
            return 1;
        }
    }

    const uint64_t start_ns = now_ns();
    bool dumped = false;
    bool quit = false;
    int loops = 0;

    while (!quit) {
        loops++;
        SDL_Event ev;
        while (!headless && SDL_PollEvent(&ev)) {
            if (ev.type == SDL_EVENT_QUIT) {
                quit = true;
            } else if (ev.type == SDL_EVENT_KEY_DOWN || ev.type == SDL_EVENT_KEY_UP) {
                const bool pressed = (ev.type == SDL_EVENT_KEY_DOWN);
                if (ev.key.scancode == SDL_SCANCODE_F12 && pressed) {
                    /* on-demand screenshot */
                    int32_t w = 0, h = 0;
                    const uint32_t *fb = api.get_framebuffer(&w, &h);
                    dump_ppm(dump_path ? dump_path : "/tmp/vice_viewer_frame.ppm", fb, w, h);
                } else if (ev.key.scancode == SDL_SCANCODE_ESCAPE && (ev.key.mod & SDL_KMOD_CTRL)) {
                    quit = true;
                } else {
                    int row, col;
                    if (matrix_lookup(ev.key.scancode, &row, &col)) {
                        fprintf(stderr, "[viewer] key scancode=%d pressed=%d -> row=%d col=%d\n",
                                ev.key.scancode, pressed, row, col);
                        api.matrix_key_event(row, col, pressed ? 1 : 0);
                    } else {
                        fprintf(stderr, "[viewer] key scancode=%d pressed=%d UNMAPPED\n",
                                ev.key.scancode, pressed);
                    }
                }
            }
        }

        int32_t w = 0, h = 0;
        const uint32_t *fb = api.get_framebuffer(&w, &h);
        if (fb != NULL && w > 0 && h > 0 && !headless) {
            if (texture == NULL || tex_w != w || tex_h != h) {
                if (texture != NULL) SDL_DestroyTexture(texture);
                texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32,
                                             SDL_TEXTUREACCESS_STREAMING, w, h);
                tex_w = w;
                tex_h = h;
            }
            if (texture != NULL) {
                SDL_UpdateTexture(texture, NULL, fb, w * (int)sizeof(uint32_t));
                SDL_RenderClear(renderer);
                SDL_RenderTexture(renderer, texture, NULL, NULL);
                SDL_RenderPresent(renderer);
            }
        }

        const double elapsed_s = (double)(now_ns() - start_ns) / 1e9;
        if (dump_path != NULL && !dumped && elapsed_s >= (double)dump_after_seconds) {
            dump_ppm(dump_path, fb, w, h);
            dumped = true;
            if (headless) quit = true; /* headless dump-and-exit */
        }
        if (run_seconds > 0 && elapsed_s >= (double)run_seconds) {
            quit = true;
        }
        if (!api.is_running()) {
            fprintf(stderr, "[viewer] core stopped running\n");
            quit = true;
        }

        if (headless) sleep_ms(16); else sleep_ms(1000 / 60);

        if (loops % 60 == 0) {
            printf("[viewer] t=%.1fs fps=%d audio_level=%d frame=%dx%d\n",
                   elapsed_s, api.get_fps(), api.get_audio_level(), w, h);
        }
    }

    if (dump_path != NULL && !dumped) {
        int32_t w = 0, h = 0;
        const uint32_t *fb = api.get_framebuffer(&w, &h);
        dump_ppm(dump_path, fb, w, h);
    }

    api.stop();
    if (texture != NULL) SDL_DestroyTexture(texture);
    if (renderer != NULL) SDL_DestroyRenderer(renderer);
    if (window != NULL) SDL_DestroyWindow(window);
    SDL_Quit();
    dlclose(api.handle);
    printf("[viewer] core mode exiting\n");
    return 0;
}

/* ------------------------------------------------------------------ */
/* vsid (libvicecore_vsid.so) mode                                     */
/* ------------------------------------------------------------------ */

typedef void (*fn_vice_vsid_init)(const char *);
typedef int32_t (*fn_vice_vsid_launch)(const char *, const char *);
typedef void (*fn_vice_vsid_set_paused)(int32_t);
typedef int32_t (*fn_vice_vsid_is_running)(void);
typedef int32_t (*fn_vice_vsid_get_audio_level)(void);
typedef int32_t (*fn_vice_vsid_get_fps)(void);

struct vsid_api {
    void *handle;
    fn_vice_vsid_init init;
    fn_vice_vsid_launch launch;
    fn_vice_vsid_set_paused set_paused;
    fn_vice_vsid_is_running is_running;
    fn_vice_vsid_get_audio_level get_audio_level;
    fn_vice_vsid_get_fps get_fps;
};

static bool vsid_api_load(struct vsid_api *api, const char *so_path) {
    memset(api, 0, sizeof(*api));
    api->handle = dlopen(so_path, RTLD_NOW | RTLD_LOCAL | RTLD_DEEPBIND);
    if (api->handle == NULL) {
        fprintf(stderr, "[viewer] dlopen(%s) failed: %s\n", so_path, dlerror());
        return false;
    }
    LOAD_SYM(api, init, "vice_vsid_init");
    LOAD_SYM(api, launch, "vice_vsid_launch");
    LOAD_SYM(api, set_paused, "vice_vsid_set_paused");
    LOAD_SYM(api, is_running, "vice_vsid_is_running");
    LOAD_SYM(api, get_audio_level, "vice_vsid_get_audio_level");
    LOAD_SYM(api, get_fps, "vice_vsid_get_fps");
    return true;
}

static int run_vsid_mode(int argc, char **argv) {
    if (argc < 5) {
        fprintf(stderr,
                "usage: %s vsid <so_path> <rom_dir> <sid_path> [wav_out] [seconds]\n",
                argv[0]);
        return 2;
    }
    const char *so_path = argv[2];
    const char *rom_dir = argv[3];
    const char *sid_path = argv[4];
    const char *wav_out = argc > 5 ? argv[5] : NULL;
    const int seconds = argc > 6 ? atoi(argv[6]) : 6;

    if (wav_out != NULL) {
        setenv("VICE_AUDIO_WAV_CAPTURE", wav_out, 1);
    }

    struct vsid_api api;
    if (!vsid_api_load(&api, so_path)) {
        return 1;
    }

    printf("[viewer] vice_vsid_init(%s)\n", rom_dir);
    api.init(rom_dir);

    printf("[viewer] vice_vsid_launch(%s)\n", sid_path);
    if (api.launch(sid_path, NULL) != 0) {
        fprintf(stderr, "[viewer] FAIL: vice_vsid_launch returned nonzero\n");
        return 1;
    }

    for (int w = 0; w < 100 && !api.is_running(); w++) sleep_ms(100);
    if (!api.is_running()) {
        fprintf(stderr, "[viewer] FAIL: vsid core never reported running\n");
        return 1;
    }
    printf("[viewer] vsid core running (no window: vsid has no video canvas)\n");

    int peak = 0;
    for (int s = 0; s < seconds; s++) {
        sleep_ms(1000);
        const int level = api.get_audio_level();
        if (level > peak) peak = level;
        printf("[viewer]   t=%ds audio_level=%d running=%d\n", s + 1, level,
               api.is_running());
        if (!api.is_running()) {
            fprintf(stderr, "[viewer] FAIL: vsid core stopped running during playback\n");
            return 1;
        }
    }

    printf("[viewer] vsid peak audio_level over %ds = %d\n", seconds, peak);
    dlclose(api.handle);
    printf("[viewer] vsid mode exiting (peak_audio_level=%d)\n", peak);
    return peak > 0 ? 0 : 3; /* 3 = ran clean but never observed nonzero audio */
}

/* ------------------------------------------------------------------ */

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s core|vsid ...\n", argv[0]);
        return 2;
    }
    if (strcmp(argv[1], "core") == 0) {
        return run_core_mode(argc, argv);
    } else if (strcmp(argv[1], "vsid") == 0) {
        return run_vsid_mode(argc, argv);
    }
    fprintf(stderr, "unknown mode '%s' (expected core|vsid)\n", argv[1]);
    return 2;
}
