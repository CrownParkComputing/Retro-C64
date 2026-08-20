/*
 * vice_bridge.c - Plain-C-ABI bridge around the VICE x64sc headless core.
 *
 * This is a from-scratch, non-JNI port of the ideas in
 * ~/AndroidStudioProjects/VICEAndroid/app/src/main/cpp/vice_android_bridge.cpp
 * (kept as read-only reference; NOT modified). It keeps the same overall
 * lifecycle and the same set of --wrap= linker hooks into VICE's normal
 * archdep_init / log_init / video_init / init_main / maincpu_mainloop /
 * vsync_do_vsync startup sequence, but:
 *
 *   - uses only C11 + pthreads, no JNI, no jstring/jboolean/jint
 *   - has no ANativeWindow / Android Surface; frames are rendered into a
 *     plain heap buffer (uint32_t RGBA8888) retrievable via
 *     vice_core_get_framebuffer()
 *   - has no AAudio backend; sound goes through audio_backend.c, a real
 *     ALSA output backend (plus optional WAV-capture for headless testing)
 *     shared with the vsid bridge
 *
 * Exposed functions use plain C types (int32_t / const char * / uint8_t *)
 * so this same source file can later be wrapped by dart:ffi and, eventually,
 * by a thin JNI shim on Android without touching the core logic.
 */

#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#include "autostart.h"
#include "attach.h"
#include "interrupt.h"
#include "joyport/joystick.h"
#include "joyport/joyport.h"
#include "kbdbuf.h"
#include "keyboard.h"
#include "machine.h"
#include "palette.h"
#include "resources.h"
#include "sound.h"
#include "tape.h"
#include "video.h"
#include "videoarch.h"
#include "vsync.h"

#include "audio_backend.h"
#include "vice_bridge.h"

extern int main_program(int argc, char **argv);

/* Declared here rather than via drive.h: that header drags in the whole
 * drive subsystem's types, and this bridge only needs the one query. */
extern int drive_check_type(unsigned int drive_type, unsigned int dnr);

/* ---------------------------------------------------------------------- */
/* Logging                                                                 */
/* ---------------------------------------------------------------------- */

#define TAG "VICEBridge"

#ifdef __ANDROID__
/* Android discards an app's stdout/stderr, so every one of these messages
 * was invisible on device -- including the ones saying why a game failed to
 * start. Route them through the platform logger instead, where
 * `adb logcat -s VICEBridge` can read them. */
#include <android/log.h>
#endif

static void bridge_log(const char *level, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
#ifdef __ANDROID__
    int priority = ANDROID_LOG_INFO;
    if (level[0] == 'W') {
        priority = ANDROID_LOG_WARN;
    } else if (level[0] == 'E') {
        priority = ANDROID_LOG_ERROR;
    }
    __android_log_vprint(priority, TAG, fmt, ap);
#else
    fprintf(stderr, "[%s] %s: ", TAG, level);
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
#endif
    va_end(ap);
}

#define LOGI(...) bridge_log("INFO", __VA_ARGS__)
#define LOGW(...) bridge_log("WARN", __VA_ARGS__)
#define LOGE(...) bridge_log("ERROR", __VA_ARGS__)

/* ---------------------------------------------------------------------- */
/* Global state (mirrors the statics in vice_android_bridge.cpp)          */
/* ---------------------------------------------------------------------- */

static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_pause_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_pause_cv = PTHREAD_COND_INITIALIZER;

/* ---------------------------------------------------------------------- */
/* Core-thread request mailboxes                                           */
/*                                                                         */
/* VICE's machine/CPU/drive state must only ever be touched from the       */
/* thread that runs its mainloop. Everything below is therefore a mailbox: */
/* the caller (an arbitrary Dart FFI/UI thread) only writes a request, and */
/* the core's OWN thread consumes it from inside the vsync hook. This is   */
/* the same pattern vice_vsid_bridge.c uses for SID hot-swapping, which is */
/* the one proven-working precedent in this tree.                          */
/* ---------------------------------------------------------------------- */

/* Media hot-swap (load a different game into an already-running core). */
static pthread_mutex_t g_pending_mutex = PTHREAD_MUTEX_INITIALIZER;
static char g_pending_media_path[1024];
static int g_pending_media_type = -1;

/* True-drive-emulation setting as the machine came up, before any media had
 * a chance to change it. The swap path restores this rather than asserting a
 * value of its own: whatever the cold start used demonstrably works, and it
 * is the only configuration the first disk of a session ever ran under. */
static int g_cold_start_tde = 1;
static atomic_bool g_media_pending = false;

/* Queued resource writes, applied on the core thread (see
 * apply_pending_resources_if_any). A ring would be overkill: the queue only
 * has to survive the gap between a UI tap and the next frame boundary, and a
 * user cannot out-type 32 settings in 20ms. If it ever did fill, dropping the
 * write and saying so beats blocking the UI thread on the emulation. */
#define PENDING_RESOURCE_MAX 32
#define PENDING_RESOURCE_NAME 64
#define PENDING_RESOURCE_VALUE 512

typedef struct {
    char name[PENDING_RESOURCE_NAME];
    bool is_string;
    int value;
    char text[PENDING_RESOURCE_VALUE];
} pending_resource_t;

static pending_resource_t g_pending_resources[PENDING_RESOURCE_MAX];
static int g_pending_resource_count = 0;
static atomic_bool g_resources_pending = false;

/* VICE builds its resource table inside init_main. resources_get_int() before
 * that dereferences a NULL hash table and takes the process with it -- a
 * SIGSEGV in resources_get_int+144 with a fault address in the low hundreds,
 * which is what a settings screen asking an un-started machine what it is set
 * to looked like. is_running() is true from the moment the core THREAD
 * starts, several stages earlier, so it is not the flag to gate on. */
static atomic_bool g_resources_ready = false;

/* Snapshot save/load. Unlike the media swap these are synchronous from the
 * caller's point of view (it needs to know whether the file was actually
 * written before it indexes it), so the caller blocks on g_snapshot_cv
 * until the core thread reports a result -- with a timeout, so a wedged or
 * not-yet-running core can never hang the UI thread forever. */
#define SNAPSHOT_OP_NONE 0
#define SNAPSHOT_OP_SAVE 1
#define SNAPSHOT_OP_LOAD 2
static char g_pending_snapshot_path[1024];
static atomic_int g_snapshot_op = SNAPSHOT_OP_NONE;
static pthread_mutex_t g_snapshot_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_snapshot_cv = PTHREAD_COND_INITIALIZER;
static int g_snapshot_result = -1;
static bool g_snapshot_complete = false;
/* Bumped by every submit_snapshot_request(); the CPU trap only publishes a
 * result for the generation it was armed for, so a request that already timed
 * out can never have a late trap scribble a stale answer over its successor. */
static uint64_t g_snapshot_seq = 0;
/* True between "trap queued with the CPU" and "trap ran". Used to keep the
 * vsync hook from queueing the same op twice, and to keep the pause gate from
 * parking the CPU before the trap it is waiting for has had a chance to run. */
static atomic_bool g_snapshot_trap_armed = false;

static char g_data_dir[1024];
static int g_joystick_port = 2;
static int g_joystick_mask = 0;

static atomic_bool g_core_started = false;
static atomic_bool g_core_running = false;
/* Set when the core aborted its own startup (see __wrap_archdep_vice_exit),
 * so the host can tell "never started" from "started and stopped". */
static atomic_bool g_core_start_failed = false;
static atomic_bool g_emulation_paused = false;
static atomic_bool g_pause_gate_active = false;
static atomic_int g_current_fps = 0;

static uint32_t *g_frame_buffer = NULL;
static size_t g_frame_buffer_capacity_pixels = 0;
static int g_frame_width = 0;
static int g_frame_height = 0;
static pthread_mutex_t g_frame_mutex = PTHREAD_MUTEX_INITIALIZER;

static atomic_uint_least64_t g_fps_window_start_ns = 0;
static atomic_int g_fps_window_frames = 0;
static atomic_int g_refresh_count = 0;

typedef struct {
    int row;
    int column;
} matrix_key_t;

/* ---------------------------------------------------------------------- */
/* Small helpers                                                          */
/* ---------------------------------------------------------------------- */

static uint16_t vice_joystick_mask(int mask) {
    uint16_t out = 0;
    if (mask & 0x01) out |= JOYPORT_UP;
    if (mask & 0x02) out |= JOYPORT_DOWN;
    if (mask & 0x04) out |= JOYPORT_LEFT;
    if (mask & 0x08) out |= JOYPORT_RIGHT;
    if (mask & 0x10) out |= JOYPORT_FIRE_1;
    if (mask & 0x20) out |= JOYPORT_FIRE_2;
    return out;
}

static unsigned int vice_joystick_port(int port) {
    return port <= 1 ? JOYPORT_1 : JOYPORT_2;
}

static bool c64_matrix_key(int key, matrix_key_t *out) {
    switch (key) {
        case 0: out->row = 7; out->column = 4; return true;
        case 1: out->row = 7; out->column = 7; return true;
        case 2: out->row = 0; out->column = 1; return true;
        case 3: out->row = 0; out->column = 4; return true;
        case 4: out->row = 0; out->column = 5; return true;
        case 5: out->row = 0; out->column = 6; return true;
        case 6: out->row = 0; out->column = 3; return true;
        default: return false;
    }
}

static void ensure_dir(const char *path) {
    if (path == NULL || path[0] == '\0') {
        return;
    }
    if (mkdir(path, 0700) != 0 && errno != EEXIST) {
        LOGW("Could not create %s: errno=%d", path, errno);
    }
}

static void prepare_vice_environment(void) {
    if (g_data_dir[0] == '\0') {
        /* Nothing to point HOME at. Silently returning here is what made the
         * missing-ROM case fatal: VICE then tried to create its XDG dirs
         * under an unset $HOME, failed, and called archdep_vice_exit ->
         * exit(). Say so loudly; vice_core_start refuses to start in this
         * state, so this should be unreachable. */
        LOGE("prepare_vice_environment: no data dir set -- vice_core_init() "
             "was never called with a ROM directory");
        return;
    }
    char cache[1152], config[1152], data[1152], state[1152];
    char cache_vice[1216], config_vice[1216], data_vice[1216], state_vice[1216];
    snprintf(cache, sizeof(cache), "%s/cache", g_data_dir);
    snprintf(config, sizeof(config), "%s/config", g_data_dir);
    snprintf(data, sizeof(data), "%s/data", g_data_dir);
    snprintf(state, sizeof(state), "%s/state", g_data_dir);
    ensure_dir(g_data_dir);
    ensure_dir(cache);
    ensure_dir(config);
    ensure_dir(data);
    ensure_dir(state);
    /* VICE writes into "<XDG dir>/vice/..." (e.g. vice.log under
     * XDG_STATE_HOME/vice/), so pre-create the per-app subdirectory too or
     * log_init's fopen() fails with ENOENT. */
    snprintf(cache_vice, sizeof(cache_vice), "%s/vice", cache);
    snprintf(config_vice, sizeof(config_vice), "%s/vice", config);
    snprintf(data_vice, sizeof(data_vice), "%s/vice", data);
    snprintf(state_vice, sizeof(state_vice), "%s/vice", state);
    ensure_dir(cache_vice);
    ensure_dir(config_vice);
    ensure_dir(data_vice);
    ensure_dir(state_vice);
    setenv("HOME", g_data_dir, 1);
    setenv("XDG_CACHE_HOME", cache, 1);
    setenv("XDG_CONFIG_HOME", config, 1);
    setenv("XDG_DATA_HOME", data, 1);
    setenv("XDG_STATE_HOME", state, 1);
}

/* ---------------------------------------------------------------------- */
/* Real ALSA sound backend (audio_backend.c), registered under VICE's      */
/* "dummy device" slot the same way the Android build registers its AAudio */
/* backend there. audio_backend_get_level() feeds vice_core_get_audio_level. */
/* ---------------------------------------------------------------------- */

extern int sound_register_device(const sound_device_t *pdevice);

static const sound_device_t alsa_sound_device = {
    "alsa",
    audio_backend_init,
    audio_backend_write,
    NULL,
    NULL,
    NULL,
    audio_backend_close,
    audio_backend_suspend,
    audio_backend_resume,
    0,
    2,
    false
};

extern int __wrap_sound_init_dummy_device(void) {
    LOGI("Registering plain-C ALSA sound device");
    return sound_register_device(&alsa_sound_device);
}

/* ---------------------------------------------------------------------- */
/* Framebuffer capture (replaces ANativeWindow blit)                       */
/* ---------------------------------------------------------------------- */

static void blit_canvas_to_buffer(struct video_canvas_s *canvas,
                                   unsigned int xs, unsigned int ys,
                                   unsigned int xi, unsigned int yi,
                                   unsigned int w, unsigned int h) {
    if (canvas == NULL || canvas->draw_buffer == NULL || canvas->videoconfig == NULL ||
        w == 0 || h == 0) {
        return;
    }

    if (canvas->palette != NULL && canvas->palette->entries != NULL) {
        for (unsigned int i = 0; i < canvas->palette->num_entries; i++) {
            const palette_entry_t *color = &canvas->palette->entries[i];
            const uint32_t color_code = color->red | (color->green << 8) |
                                         (color->blue << 16) | (0xffU << 24);
            video_render_setphysicalcolor(canvas->videoconfig, (int)i, color_code, 32);
        }
        for (int i = 0; i < 256; i++) {
            video_render_setrawrgb(&canvas->videoconfig->color_tables, i, i, i << 8, i << 16);
        }
        video_render_setrawalpha(&canvas->videoconfig->color_tables, 0xffU << 24);
        video_render_initraw(canvas->videoconfig);
    }

    int frame_width = (int)canvas->draw_buffer->visible_width;
    int frame_height = (int)canvas->draw_buffer->visible_height;
    if (frame_width <= 0) frame_width = (int)canvas->draw_buffer->canvas_width;
    if (frame_height <= 0) frame_height = (int)canvas->draw_buffer->canvas_height;
    if (frame_width <= 0) frame_width = (int)(xi + w);
    if (frame_height <= 0) frame_height = (int)(yi + h);
    if (frame_width <= 0 || frame_height <= 0) {
        return;
    }

    const int target_x = (int)xi;
    const int target_y = (int)yi;
    if (target_x >= frame_width || target_y >= frame_height) {
        return;
    }
    const int update_width = frame_width - target_x < (int)w ? frame_width - target_x : (int)w;
    const int update_height = frame_height - target_y < (int)h ? frame_height - target_y : (int)h;
    if (update_width <= 0 || update_height <= 0) {
        return;
    }

    const uint8_t *source = canvas->draw_buffer->draw_buffer;
    const int source_pitch = (int)(canvas->draw_buffer->draw_buffer_pitch != 0
                                        ? canvas->draw_buffer->draw_buffer_pitch
                                        : canvas->draw_buffer->draw_buffer_width);
    const int source_height = (int)canvas->draw_buffer->draw_buffer_height;
    if (source == NULL || source_pitch <= 0 || source_height <= 0) {
        return;
    }
    const uint32_t *colors = canvas->videoconfig->color_tables.physical_colors;

    pthread_mutex_lock(&g_frame_mutex);
    const size_t required_pixels = (size_t)frame_width * (size_t)frame_height;
    if (g_frame_width != frame_width || g_frame_height != frame_height ||
        g_frame_buffer_capacity_pixels < required_pixels) {
        uint32_t *resized = realloc(g_frame_buffer, required_pixels * sizeof(uint32_t));
        if (resized == NULL) {
            pthread_mutex_unlock(&g_frame_mutex);
            return;
        }
        g_frame_buffer = resized;
        g_frame_buffer_capacity_pixels = required_pixels;
        memset(g_frame_buffer, 0, required_pixels * sizeof(uint32_t));
        g_frame_width = frame_width;
        g_frame_height = frame_height;
    }

    for (int y = 0; y < update_height; y++) {
        const int source_y = (int)ys + y;
        const int dest_y = target_y + y;
        if (source_y < 0 || source_y >= source_height || dest_y < 0 || dest_y >= frame_height) {
            continue;
        }
        const uint8_t *source_row = source + (size_t)source_y * source_pitch;
        uint32_t *dest_row = g_frame_buffer + (size_t)dest_y * frame_width;
        for (int x = 0; x < update_width; x++) {
            const int source_x = (int)xs + x;
            const int dest_x = target_x + x;
            if (source_x < 0 || source_x >= source_pitch || dest_x < 0 || dest_x >= frame_width) {
                continue;
            }
            dest_row[dest_x] = colors[source_row[source_x]];
        }
    }
    pthread_mutex_unlock(&g_frame_mutex);

    const int refresh_no = atomic_fetch_add(&g_refresh_count, 1) + 1;
    if (refresh_no <= 8) {
        LOGI("refresh #%d xs=%u ys=%u xi=%u yi=%u w=%u h=%u frame=%dx%d",
             refresh_no, xs, ys, xi, yi, w, h, frame_width, frame_height);
    }

    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    const uint64_t now_ns = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
    uint64_t window_start = atomic_load_explicit(&g_fps_window_start_ns, memory_order_acquire);
    if (window_start == 0) {
        atomic_store_explicit(&g_fps_window_start_ns, now_ns, memory_order_release);
        atomic_store_explicit(&g_fps_window_frames, 0, memory_order_release);
        window_start = now_ns;
    }
    const int frames = atomic_fetch_add(&g_fps_window_frames, 1) + 1;
    if (now_ns - window_start >= 1000000000ULL) {
        const uint64_t elapsed = now_ns - window_start;
        const int fps = (int)(((uint64_t)frames * 1000000000ULL + elapsed / 2) / elapsed);
        atomic_store_explicit(&g_current_fps, fps, memory_order_release);
        atomic_store_explicit(&g_fps_window_start_ns, now_ns, memory_order_release);
        atomic_store_explicit(&g_fps_window_frames, 0, memory_order_release);
    }
}

extern void __wrap_video_canvas_refresh(struct video_canvas_s *canvas,
                                         unsigned int xs, unsigned int ys,
                                         unsigned int xi, unsigned int yi,
                                         unsigned int w, unsigned int h) {
    blit_canvas_to_buffer(canvas, xs, ys, xi, yi, w, h);
}

/* ---------------------------------------------------------------------- */
/* Startup-sequence --wrap= hooks (same idea as the Android bridge)        */
/* ---------------------------------------------------------------------- */

extern int __real_archdep_init(int *argc, char **argv);
/* The core thread, so __wrap_archdep_vice_exit can tell whether it is being
 * called on the thread it is allowed to unwind. */
static pthread_t g_core_tid;
static atomic_bool g_core_tid_valid = false;

/* VICE's archdep_vice_exit() calls libc exit(). In the standalone emulator
 * that is correct; inside this shared library it is fatal, because exit()
 * runs __cxa_finalize over EVERY loaded library -- including libflutter.so,
 * whose static destructors then double-free and abort the whole app with
 * "scudo ERROR: invalid chunk state when deallocating".
 *
 * That is not hypothetical: with no ROMs installed, archdep_init ->
 * archdep_create_user_cache_dir -> archdep_vice_exit(1) -> exit() killed the
 * entire Flutter process on launching a game. Any VICE init failure did.
 *
 * So the exit is contained here: mark the core stopped and unwind just the
 * core thread. main_program never returns, which is what VICE expects of
 * this function, and the host survives to report the failure.
 */
extern void __real_archdep_vice_exit(int exit_code);
extern void __wrap_archdep_vice_exit(int exit_code) {
    LOGE("archdep_vice_exit(%d) intercepted -- VICE wanted to exit(); "
         "unwinding the core thread instead of killing the process",
         exit_code);
    atomic_store_explicit(&g_core_running, false, memory_order_release);
    atomic_store_explicit(&g_resources_ready, false, memory_order_release);
    atomic_store_explicit(&g_core_start_failed, true, memory_order_release);

    if (atomic_load_explicit(&g_core_tid_valid, memory_order_acquire) &&
        pthread_equal(pthread_self(), g_core_tid)) {
        pthread_exit(NULL);
    }

    /* Called from somewhere other than the core thread. Unwinding an
     * arbitrary caller would be worse than returning, so return and let the
     * caller carry on -- still better than taking the process down. */
    LOGE("archdep_vice_exit called off the core thread; returning instead");
}

extern int __wrap_archdep_init(int *argc, char **argv) {
    LOGI("stage archdep_init begin argc=%d", argc ? *argc : -1);
    int result = __real_archdep_init(argc, argv);
    LOGI("stage archdep_init end result=%d", result);
    return result;
}

extern int __real_log_init(void);
extern int __wrap_log_init(void) {
    LOGI("stage log_init begin");
    int result = __real_log_init();
    LOGI("stage log_init end result=%d", result);
    return result;
}

extern int __real_video_init(void);
extern int __wrap_video_init(void) {
    LOGI("stage video_init begin");
    int result = __real_video_init();
    LOGI("stage video_init end result=%d", result);
    return result;
}

extern int __real_init_main(void);
extern int __wrap_init_main(void) {
    LOGI("stage init_main begin");
    int result = __real_init_main();
    if (result == 0) {
        atomic_store_explicit(&g_resources_ready, true, memory_order_release);
    }
    LOGI("stage init_main end result=%d", result);
    return result;
}

extern struct video_canvas_s *__real_video_canvas_create(struct video_canvas_s *canvas,
                                                           unsigned int *width,
                                                           unsigned int *height,
                                                           int mapped);
extern struct video_canvas_s *__wrap_video_canvas_create(struct video_canvas_s *canvas,
                                                           unsigned int *width,
                                                           unsigned int *height,
                                                           int mapped) {
    LOGI("stage video_canvas_create begin requested=%ux%u", width ? *width : 0, height ? *height : 0);
    struct video_canvas_s *result = __real_video_canvas_create(canvas, width, height, mapped);
    LOGI("stage video_canvas_create end result=%p size=%ux%u", (void *)result,
         width ? *width : 0, height ? *height : 0);
    return result;
}

extern char __wrap_video_canvas_can_resize(struct video_canvas_s *canvas) {
    (void)canvas;
    return 1;
}

extern void __real_video_canvas_resize(struct video_canvas_s *canvas, char resize_canvas);
extern void __wrap_video_canvas_resize(struct video_canvas_s *canvas, char resize_canvas) {
    if (canvas != NULL && canvas->draw_buffer != NULL) {
        if (canvas->draw_buffer->canvas_width == 0 && canvas->draw_buffer->visible_width != 0) {
            canvas->draw_buffer->canvas_width = canvas->draw_buffer->visible_width;
        }
        if (canvas->draw_buffer->canvas_height == 0 && canvas->draw_buffer->visible_height != 0) {
            canvas->draw_buffer->canvas_height = canvas->draw_buffer->visible_height;
        }
        if (canvas->draw_buffer->canvas_physical_width == 0 && canvas->draw_buffer->canvas_width != 0) {
            canvas->draw_buffer->canvas_physical_width = canvas->draw_buffer->canvas_width;
        }
        if (canvas->draw_buffer->canvas_physical_height == 0 && canvas->draw_buffer->canvas_height != 0) {
            canvas->draw_buffer->canvas_physical_height = canvas->draw_buffer->canvas_height;
        }
        LOGI("stage video_canvas_resize resize=%d canvas=%ux%u visible=%ux%u",
             resize_canvas,
             canvas->draw_buffer->canvas_width, canvas->draw_buffer->canvas_height,
             canvas->draw_buffer->visible_width, canvas->draw_buffer->visible_height);
    }
    __real_video_canvas_resize(canvas, resize_canvas);
}

extern void __real_maincpu_mainloop(void);
extern void __wrap_maincpu_mainloop(void) {
    LOGI("stage maincpu_mainloop begin");
    __real_maincpu_mainloop();
    LOGE("stage maincpu_mainloop returned");
}

/* ---------------------------------------------------------------------- */
/* Core-thread request handlers                                            */
/*                                                                         */
/* Everything in this block runs on the VICE core's own mainloop thread    */
/* (called from the vsync hook, i.e. from inside maincpu_mainloop's call   */
/* stack), which is the only thread allowed to touch machine state.        */
/* ---------------------------------------------------------------------- */

/* Load a different title into the running core. Mirrors what VICE's own UI
 * backends do for "smart attach": detach whatever is currently mounted so a
 * stale image can never be autostarted instead of the new one, set the
 * per-media-type resources the initial vice_core_start() command line sets
 * (VFS PRG injection needs true drive emulation OFF on unit 8; disk/tape
 * want it ON), then let autostart_autodetect() do the attach + reboot. It
 * calls reboot_for_autostart() internally, which is what actually triggers
 * the machine reset -- so no separate machine_trigger_reset() is needed or
 * wanted here (an extra reset would race the autostart state machine). */
static void remember_cold_start_tde(void);

static void apply_pending_media_if_any(void) {
    if (!atomic_load_explicit(&g_media_pending, memory_order_acquire)) {
        return;
    }

    char path[sizeof(g_pending_media_path)];
    int media_type;
    pthread_mutex_lock(&g_pending_mutex);
    snprintf(path, sizeof(path), "%s", g_pending_media_path);
    media_type = g_pending_media_type;
    pthread_mutex_unlock(&g_pending_mutex);
    atomic_store_explicit(&g_media_pending, false, memory_order_release);

    if (path[0] == '\0') {
        return;
    }

    LOGI("core thread applying pending media swap type=%d path=%s", media_type, path);
    vsync_suspend_speed_eval();

    tape_image_detach(1);
    file_system_detach_disk(8, 0);

    switch (media_type) {
        case 0: /* PRG: VFS injection, true drive emulation must be off */
            resources_set_int("AutostartPrgMode", 0);
            resources_set_int_sprintf("Drive%dTrueEmulation", 0, 8);
            break;
        case 1: /* DISK */
        case 2: /* TAPE */
            /* Restore whatever a cold start uses rather than forcing true
             * drive emulation on.
             *
             * Forcing it on is what broke every disk after the first: with
             * TDE on, autostart needs a real 1541, so it tries to change the
             * drive type and VICE answers "Failed to set drive type" -- a
             * type change is refused when that drive's ROM is not loaded in
             * the running machine. From there device 8 does not exist and
             * the game dies on ?DEVICE NOT PRESENT, which reads as a broken
             * .d64 rather than as a setting we changed. The first disk of a
             * session worked precisely because nothing had forced TDE yet.
             *
             * Only the PRG path above genuinely needs to touch this, and it
             * turns TDE OFF, so putting it back is all that is required. */
            resources_set_int_sprintf("Drive%dTrueEmulation", g_cold_start_tde, 8);
            break;
        default:
            break;
    }

    /* Report what the drive actually looks like now. When a disk still fails
     * after this, these three numbers say which of the two possibilities it
     * is -- a drive type that would not change, or a ROM that never loaded --
     * without needing another round of guessing from the outside. */
    {
        int tde = -1, type = -1, fsdev = -1;
        resources_get_int_sprintf("Drive%dTrueEmulation", &tde, 8);
        resources_get_int_sprintf("Drive%dType", &type, 8);
        resources_get_int_sprintf("FileSystemDevice%d", &fsdev, 8);

        /* The decisive one. VICE refuses a drive-type change unless that
         * type's ROM is loaded in the running machine (drive_check_type ->
         * drive_rom_check_loaded), and "Error - Failed to set drive type"
         * does not say which of the two it is. Tapes and PRGs need no drive
         * at all, which is exactly why they work while every .d64 fails.
         *
         * rom1541=0 means DRIVES/dos1541-325302-01+901229-05.bin was never
         * loaded, whatever the file browser shows, and the fault is in
         * finding it. rom1541=1 means it IS loaded and the type change is
         * being refused for another reason. */
        const int rom1541 = drive_check_type(1541 /* DRIVE_TYPE_1541 */, 0);
        LOGI("drive 8 before autostart: truedrive=%d type=%d fsdevice=%d "
             "rom1541=%d", tde, type, fsdev, rom1541);
    }

    const int result = autostart_autodetect(path, NULL, 0, AUTOSTART_MODE_RUN);
    if (result < 0) {
        LOGE("media swap: autostart_autodetect failed for %s", path);
    } else {
        LOGI("media swap applied: %s", path);
    }
}

/* The snapshot itself, run as a 6510 CPU trap.
 *
 * This MUST NOT be called straight from the vsync hook, which is where it
 * used to live. vsync_do_vsync() runs from inside the CPU emulation, and
 * VICE's interpreter (6510core.c) keeps the 6510 registers -- PC, A, X, Y,
 * SP, flags -- in *local variables* of maincpu_mainloop() for the duration
 * of a run, syncing them to the global maincpu_regs only at defined points.
 * So a snapshot taken at vsync time serialises stale registers, and a
 * snapshot restored at vsync time has its restored registers immediately
 * overwritten by the interpreter's untouched locals when it resumes. The
 * result is a machine that has the save point's RAM but the *current*
 * program counter: it looks like nothing was restored, and how wrong it
 * looks depends on where the CPU happened to be -- which is why identical
 * runs gave different mismatch ratios.
 *
 * VICE's own UIs never call machine_read_snapshot() directly for this
 * reason; they go through interrupt_maincpu_trigger_trap() (see
 * arch/gtk3/uisnapshot.c). A trap is dispatched at an instruction boundary
 * with EXPORT_REGISTERS() before and IMPORT_REGISTERS() after it, so the
 * saved registers are current and the restored ones actually take. */
/* Whether the media attached right now survives a snapshot round-trip.
 *
 * VICE cannot snapshot a T64 tape image: tape_snapshot_write_t64image_module()
 * in src/tape/tape-snapshot.c is a stub that logs "T64 snapshot support is not
 * implemented" and then returns 0 anyway, with an upstream comment saying it
 * "should be -1, but that would make snapshots with default settings fail".
 * So the write silently succeeds while the tape's contents and position go
 * nowhere, and the restore comes back with a datasette pointing at nothing.
 * A game that has finished loading into RAM would often survive that, but a
 * game that streams further data off the tape would not, and we cannot tell
 * the two apart from here -- so refuse, and let the caller offer a restart.
 *
 * TAP tape images, disk images and VFS-injected PRGs are all fine: TAP and
 * disk images are written into the snapshot in full (tape-snapshot.c's
 * TAPIMAGE module, drive-snapshot.c's IMAGE/GCRIMAGE modules), and a PRG has
 * been copied into RAM by the time anything is worth saving. */
static bool media_is_snapshottable(void) {
    /* tape_image_dev is indexed by (datasette unit - 1); VICE builds two
     * entries, and the C64 only ever uses the first. Check both so this stays
     * right if a second datasette is ever wired up. */
    for (int port = 0; port < 2; port++) {
        const tape_image_t *image = tape_image_dev[port];
        if (image != NULL && image->name != NULL && image->type == TAPE_TYPE_T64) {
            LOGW("refusing snapshot: a T64 tape image (%s) is attached and VICE "
                 "has no T64 snapshot support, so the restore would not work",
                 image->name);
            return false;
        }
    }
    return true;
}

static void snapshot_trap(uint16_t addr, void *data) {
    (void)addr;
    (void)data;

    char path[sizeof(g_pending_snapshot_path)];
    uint64_t seq;
    pthread_mutex_lock(&g_snapshot_mutex);
    snprintf(path, sizeof(path), "%s", g_pending_snapshot_path);
    seq = g_snapshot_seq;
    pthread_mutex_unlock(&g_snapshot_mutex);

    const int op = atomic_load_explicit(&g_snapshot_op, memory_order_acquire);

    vsync_suspend_speed_eval();
    int result;
    if (op == SNAPSHOT_OP_SAVE) {
        if (!media_is_snapshottable()) {
            /* Deliberately BEFORE machine_write_snapshot: writing a file we
             * know will not restore is worse than writing none, because the
             * app would then list it as resumable. */
            result = VICE_SNAPSHOT_UNSUPPORTED_MEDIA;
        } else {
            /* save_roms=0 (ROMs are ours and identical on reload),
             * save_disks=1 so a game that streams from its disk image still
             * resumes correctly -- and so that a snapshot restored after the
             * user has played something else in between brings its own disk
             * back with it -- event_mode=0 (not an event-history recording). */
            result = machine_write_snapshot(path, 0, 1, 0);
        }
        LOGI("snapshot save path=%s result=%d", path, result);
    } else if (op == SNAPSHOT_OP_LOAD) {
        result = machine_read_snapshot(path, 0);
        LOGI("snapshot load path=%s result=%d", path, result);
    } else {
        LOGW("snapshot trap ran with no op pending");
        result = -1;
    }
    vsync_suspend_speed_eval();

    atomic_store_explicit(&g_snapshot_op, SNAPSHOT_OP_NONE, memory_order_release);
    atomic_store_explicit(&g_snapshot_trap_armed, false, memory_order_release);

    pthread_mutex_lock(&g_snapshot_mutex);
    if (g_snapshot_seq == seq) {
        g_snapshot_result = result;
        g_snapshot_complete = true;
        pthread_cond_broadcast(&g_snapshot_cv);
    } else {
        LOGW("snapshot trap result dropped: request seq %llu superseded",
             (unsigned long long)seq);
    }
    pthread_mutex_unlock(&g_snapshot_mutex);
}

/* Runs on the core thread from the vsync hook: only *queues* the trap, which
 * the CPU then runs at its next instruction boundary. */
static void apply_pending_snapshot_if_any(void) {
    if (atomic_load_explicit(&g_snapshot_op, memory_order_acquire) == SNAPSHOT_OP_NONE) {
        return;
    }
    if (atomic_exchange_explicit(&g_snapshot_trap_armed, true, memory_order_acq_rel)) {
        return; /* already queued with the CPU, waiting for it to run */
    }
    interrupt_maincpu_trigger_trap(snapshot_trap, NULL);
}

/* Both mailboxes, in the order that matters: a media swap that arrived
 * alongside a snapshot request should not have its fresh machine state
 * overwritten by a snapshot load queued for the previous title. */
static void apply_pending_resources_if_any(void) {
    if (!atomic_load_explicit(&g_resources_pending, memory_order_acquire)) {
        return;
    }

    pending_resource_t batch[PENDING_RESOURCE_MAX];
    int count;
    pthread_mutex_lock(&g_pending_mutex);
    count = g_pending_resource_count;
    memcpy(batch, g_pending_resources, sizeof(pending_resource_t) * (size_t)count);
    g_pending_resource_count = 0;
    pthread_mutex_unlock(&g_pending_mutex);
    atomic_store_explicit(&g_resources_pending, false, memory_order_release);

    for (int i = 0; i < count; i++) {
        int rc;
        if (batch[i].is_string) {
            rc = resources_set_string(batch[i].name, batch[i].text);
            LOGI("resource %s = \"%s\" (rc=%d)", batch[i].name, batch[i].text, rc);
        } else {
            rc = resources_set_int(batch[i].name, batch[i].value);
            LOGI("resource %s = %d (rc=%d)", batch[i].name, batch[i].value, rc);
        }
        /* Not fatal, and deliberately not silent: a resource VICE rejects
         * (wrong type, out of range, not valid for this machine) is a bug in
         * the front end's table, and the log is where that gets found. */
        if (rc < 0) {
            LOGE("resource %s refused by the core", batch[i].name);
        }
    }
}

static int32_t queue_resource(const char *name, bool is_string, int value,
                              const char *text) {
    if (name == NULL || name[0] == '\0') {
        return -1;
    }
    if (!atomic_load_explicit(&g_resources_ready, memory_order_acquire)) {
        return -1;
    }
    int32_t result = 0;
    pthread_mutex_lock(&g_pending_mutex);
    if (g_pending_resource_count >= PENDING_RESOURCE_MAX) {
        result = -1;
    } else {
        pending_resource_t *slot = &g_pending_resources[g_pending_resource_count++];
        snprintf(slot->name, sizeof(slot->name), "%s", name);
        slot->is_string = is_string;
        slot->value = value;
        snprintf(slot->text, sizeof(slot->text), "%s", text ? text : "");
    }
    pthread_mutex_unlock(&g_pending_mutex);
    if (result == 0) {
        atomic_store_explicit(&g_resources_pending, true, memory_order_release);
    } else {
        LOGE("resource queue full; dropped %s", name);
    }
    return result;
}

int32_t vice_core_get_resource_int(const char *name, int32_t *out_value) {
    int value = 0;
    if (name == NULL || out_value == NULL) {
        return -1;
    }
    if (!atomic_load_explicit(&g_resources_ready, memory_order_acquire)) {
        return -1;
    }
    if (resources_get_int(name, &value) < 0) {
        return -1;
    }
    *out_value = (int32_t)value;
    return 0;
}

int32_t vice_core_set_resource_int(const char *name, int32_t value) {
    return queue_resource(name, false, (int)value, NULL);
}

int32_t vice_core_get_resource_string(const char *name, char *out_buf,
                                      int32_t out_len) {
    const char *value = NULL;
    if (name == NULL || out_buf == NULL || out_len <= 0) {
        return -1;
    }
    if (!atomic_load_explicit(&g_resources_ready, memory_order_acquire)) {
        out_buf[0] = '\0';
        return -1;
    }
    if (resources_get_string(name, &value) < 0 || value == NULL) {
        out_buf[0] = '\0';
        return -1;
    }
    snprintf(out_buf, (size_t)out_len, "%s", value);
    return 0;
}

int32_t vice_core_set_resource_string(const char *name, const char *value) {
    return queue_resource(name, true, 0, value);
}

int32_t vice_core_dump_resources(const char *path) {
    if (path == NULL || path[0] == '\0') {
        return -1;
    }
    if (!atomic_load_explicit(&g_resources_ready, memory_order_acquire)) {
        /* Before init_main there IS no resource table -- dumping it would
         * walk a NULL hash table, not produce an empty file. */
        LOGE("resource dump requested with no running core");
        return -1;
    }
    const int rc = resources_dump(path);
    LOGI("resource dump -> %s (rc=%d)", path, rc);
    return rc < 0 ? -1 : 0;
}

static void pump_core_requests(void) {
    /* Latch the machine's own drive configuration before any swap can alter
     * it. Runs on the core thread, after init_main, which is the first point
     * the resource is meaningful. */
    remember_cold_start_tde();
    apply_pending_resources_if_any();
    apply_pending_media_if_any();
    apply_pending_snapshot_if_any();
}

/* Is there core work outstanding that needs the CPU to actually run? */
static bool core_request_pending(void) {
    return atomic_load_explicit(&g_media_pending, memory_order_acquire) ||
           atomic_load_explicit(&g_resources_pending, memory_order_acquire) ||
           atomic_load_explicit(&g_snapshot_op, memory_order_acquire) != SNAPSHOT_OP_NONE ||
           atomic_load_explicit(&g_snapshot_trap_armed, memory_order_acquire);
}

static void wait_while_emulation_paused(void) {
    if (!atomic_load_explicit(&g_emulation_paused, memory_order_acquire)) {
        return;
    }
    LOGI("pause gate entered");
    sound_suspend();
    vsync_suspend_speed_eval();

    pthread_mutex_lock(&g_pause_mutex);
    atomic_store_explicit(&g_pause_gate_active, true, memory_order_release);
    pthread_cond_broadcast(&g_pause_cv);
    while (atomic_load_explicit(&g_emulation_paused, memory_order_acquire) &&
           !core_request_pending()) {
        /* Timed rather than indefinite: while parked here this thread is
         * still the only one allowed to service the request mailboxes, and
         * the save-state feature specifically needs a snapshot written for
         * a title the user has just paused. Waking 20x/second to check
         * costs nothing measurable and removes a whole class of deadlock
         * (caller blocked on a snapshot that the paused core would never
         * pick up). */
        struct timespec deadline;
        clock_gettime(CLOCK_REALTIME, &deadline);
        deadline.tv_nsec += 50 * 1000 * 1000;
        if (deadline.tv_nsec >= 1000000000L) {
            deadline.tv_sec += 1;
            deadline.tv_nsec -= 1000000000L;
        }
        pthread_cond_timedwait(&g_pause_cv, &g_pause_mutex, &deadline);
    }
    /* Leaving the gate with a request outstanding is deliberate, not a
     * missed wakeup: snapshots are now run as CPU traps, and a trap only
     * fires when the CPU executes instructions. Parking here with one queued
     * would deadlock the caller until its 10s timeout. Returning instead
     * lets the emulator run one frame so the trap dispatches; the gate is
     * re-entered at the very next vsync because the pause flag is still set,
     * so the user sees at most a single frame of motion. */
    atomic_store_explicit(&g_pause_gate_active, false, memory_order_release);
    pthread_mutex_unlock(&g_pause_mutex);

    sound_resume();
    vsync_suspend_speed_eval();
    LOGI("pause gate resumed");
}

extern int vsync_get_warp_mode(void);
extern void vsync_set_warp_mode(int val);
extern void __real_vsync_do_vsync(struct video_canvas_s *canvas);
extern void __wrap_vsync_do_vsync(struct video_canvas_s *canvas) {
    pump_core_requests();
    wait_while_emulation_paused();
    __real_vsync_do_vsync(canvas);
}

/* ---------------------------------------------------------------------- */
/* VICE argv construction + core thread                                    */
/* ---------------------------------------------------------------------- */

typedef struct {
    char **argv;
    int argc;
} core_thread_args_t;

static void *core_thread_main(void *arg) {
    core_thread_args_t *targs = (core_thread_args_t *)arg;
    g_core_tid = pthread_self();
    atomic_store_explicit(&g_core_tid_valid, true, memory_order_release);
    prepare_vice_environment();
    atomic_store_explicit(&g_core_running, true, memory_order_release);
    LOGI("Starting VICE main_program argc=%d", targs->argc);

    /* VICE's main_program() (src/main.c) left-shifts the argv array we
     * hand it *in place* to strip already-consumed leading options
     * (-default, -verbose, ...), shrinking its own local argc as it goes.
     * That shift is safe from VICE's point of view (it never reads past
     * its own reduced argc afterwards), but it does not clear every
     * vacated slot: the very last original slot is left holding a stale
     * pointer that is now a duplicate of one that got relocated earlier
     * in the array. If we let VICE mutate the exact array we later walk
     * with our own (original, pre-call) argc to free() each string, we
     * walk into that stale duplicate slot and free an already-freed
     * pointer a second time (glibc "double free detected in tcache").
     *
     * Fix: give VICE a disposable scratch copy of the pointer array so
     * its in-place rewriting can never corrupt targs->argv, which is the
     * array we actually own and use for cleanup below. */
    const size_t argv_bytes = (size_t)(targs->argc + 1) * sizeof(char *);
    char **argv_scratch = malloc(argv_bytes);
    char **argv_for_vice = targs->argv;
    if (argv_scratch != NULL) {
        memcpy(argv_scratch, targs->argv, argv_bytes);
        argv_for_vice = argv_scratch;
    } else {
        LOGW("core_thread_main: scratch argv allocation failed, passing owned array directly");
    }

    int result = main_program(targs->argc, argv_for_vice);
    free(argv_scratch);

    atomic_store_explicit(&g_core_running, false, memory_order_release);
    atomic_store_explicit(&g_resources_ready, false, memory_order_release);
    LOGE("VICE main_program returned %d", result);

    for (int i = 0; i < targs->argc; i++) {
        free(targs->argv[i]);
    }
    free(targs->argv);
    free(targs);
    return NULL;
}

static void start_core_thread(char **args, int argc) {
    core_thread_args_t *targs = calloc(1, sizeof(core_thread_args_t));
    targs->argv = calloc((size_t)argc + 1, sizeof(char *));
    for (int i = 0; i < argc; i++) {
        targs->argv[i] = strdup(args[i]);
    }
    targs->argv[argc] = NULL;
    targs->argc = argc;

    pthread_t thread;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&thread, &attr, core_thread_main, targs);
    pthread_attr_destroy(&attr);
}

/* ---------------------------------------------------------------------- */
/* Public C API (vice_bridge.h)                                            */
/* ---------------------------------------------------------------------- */

/* What the CORE can see in one of its ROM subdirectories, listed from C.
 *
 * The Dart side already reports whether a ROM is installed, and the machine
 * already reports whether the 1541 ROM loaded (rom1541= in the two drive
 * lines below). When those two disagree -- the Paths screen says "Installed"
 * and the drive still answers ?DEVICE NOT PRESENT -- nothing said which of
 * the three possible reasons it was: the core was handed a different
 * directory than Dart checked, the file is there under a name VICE will not
 * look for, or it is there and unreadable. All three look identical from
 * either end, and on iOS there is no shell to go and look with.
 *
 * So list it from inside the process that actually does the loading, at the
 * exact path VICE is about to search (findpath appends <subpath>/<name> to
 * each element of the Directory resource -- see src/findpath.c). ENOENT here
 * is the answer on its own: the core is looking somewhere Dart never wrote.
 */
static void log_rom_subdir(const char *subdir) {
    char path[1152];
    snprintf(path, sizeof(path), "%s/%s", g_data_dir, subdir);

    DIR *d = opendir(path);
    if (d == NULL) {
        LOGE("rom dir %s: cannot open (errno=%d)", path, errno);
        return;
    }

    /* One line, not one per file: a DRIVES folder holds a dozen ROMs and the
     * log is read by eye on a phone. */
    char names[768];
    size_t used = 0;
    int count = 0;
    bool truncated = false;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        count++;
        if (truncated) continue; /* keep counting, stop naming */
        const int n = snprintf(names + used, sizeof(names) - used, "%s%s",
                               used > 0 ? " " : "", e->d_name);
        if (n < 0 || (size_t)n >= sizeof(names) - used) {
            /* Say so rather than ending mid-filename: a silently clipped list
             * reads as "that ROM is not there" when it is simply off the end.
             * C64/ overflows this routinely; DRIVES/ does not. */
            names[used] = '\0';
            truncated = true;
            continue;
        }
        used += (size_t)n;
    }
    closedir(d);
    names[used] = '\0';
    LOGI("rom dir %s: %d file(s): %s%s", path, count,
         count > 0 ? names : "(empty)", truncated ? " ...(list truncated)" : "");
}

void vice_core_init(const char *rom_dir) {
    pthread_mutex_lock(&g_mutex);
    if (rom_dir != NULL) {
        snprintf(g_data_dir, sizeof(g_data_dir), "%s", rom_dir);
    } else {
        g_data_dir[0] = '\0';
    }
    LOGI("Initialized bridge with rom/data dir: %s", g_data_dir);
    if (g_data_dir[0] != '\0') {
        log_rom_subdir("C64");
        log_rom_subdir("DRIVES");
    }
    pthread_mutex_unlock(&g_mutex);
}

/* Wakes the core thread if it happens to be parked in the pause gate, so a
 * request queued while the user is browsing the workbench is picked up
 * without waiting for the gate's own 50ms poll. */
static void nudge_core_thread(void) {
    pthread_mutex_lock(&g_pause_mutex);
    pthread_cond_broadcast(&g_pause_cv);
    pthread_mutex_unlock(&g_pause_mutex);
}

int32_t vice_core_start(int32_t media_type, const char *media_path, const char *command_line) {
    /* Refuse to start without a data directory. VICE would get as far as
     * archdep_init, fail to create its XDG dirs under an unset $HOME, and
     * call archdep_vice_exit -- which used to take the whole host process
     * with it. __wrap_archdep_vice_exit now contains that, but a core that
     * cannot possibly boot should never be started in the first place, and
     * the host gets a -1 it can turn into "ROMs missing" instead of a
     * window that dies. */
    if (g_data_dir[0] == '\0') {
        LOGE("vice_core_start: refusing to start -- no ROM/data directory. "
             "vice_core_init() must be called with a readable ROM dir first "
             "(the C64 and DRIVES ROMs are missing).");
        return -1;
    }
    if (atomic_exchange_explicit(&g_core_started, true, memory_order_acq_rel)) {
        /* Already started: this is the user picking a DIFFERENT title from
         * the library. VICE has no supported way to tear down and re-run
         * main_program() in-process, and calling attach/autostart from this
         * (arbitrary caller) thread while the core thread runs is exactly
         * the unsafe thing vice_vsid_bridge.c avoids. So queue the swap for
         * the core's own thread instead -- see apply_pending_media_if_any().
         * A newer request overwrites an older unconsumed one, which also
         * coalesces rapid double-taps down to the last title picked. */
        if (!atomic_load_explicit(&g_core_running, memory_order_acquire)) {
            LOGW("vice_core_start: core was started but is no longer running");
            return -1;
        }
        if (media_path == NULL || media_path[0] == '\0') {
            LOGW("vice_core_start: core already running and no media given");
            return -1;
        }
        LOGI("vice_core_start: queuing media swap type=%d path=%s", media_type, media_path);
        pthread_mutex_lock(&g_pending_mutex);
        snprintf(g_pending_media_path, sizeof(g_pending_media_path), "%s", media_path);
        g_pending_media_type = (int)media_type;
        pthread_mutex_unlock(&g_pending_mutex);
        atomic_store_explicit(&g_media_pending, true, memory_order_release);
        nudge_core_thread();
        return 0;
    }

    const char *args[32];
    int argc = 0;
    args[argc++] = "x64sc";
    args[argc++] = "-default";
    /* NOT -verbose. It used to be, from when the only way to see anything was
     * to squint at logcat and more output was strictly better. That stopped
     * being true when the app grew a Logs page users are asked to send in:
     * -verbose makes vicii_chip_model_set() dump its entire cycle table
     * through log_verbose() at every start -- around 126 lines of
     * "VIC-II: 44 Phi1 $0f4 27 *-------- FetchG" before the machine has done
     * anything -- which buries the handful of lines a bug report needs and
     * bloats the file the user has to mail.
     *
     * Nothing diagnostic is lost: the messages that matter are log_message(),
     * not log_verbose(), so ROM loading, "D64 disk image recognised", the
     * unit-8 attach and every warning still print. */
    /* VICE's log_helper() has a NULL-deref bug (log.c) when log_colorize is
     * on but stdout is not a terminal (e.g. piped/redirected, as when run
     * headless from another process): it computes the "no color" strings
     * only when log_to_file || !log_colorize, but then falls back to those
     * same (uncomputed, NULL) strings once archdep_default_logger_is_terminal()
     * says stdout isn't a tty. Force colorized logging off so that path is
     * never taken. */
    args[argc++] = "+logcolorize";
    args[argc++] = "+autostart-delay-random";
    args[argc++] = "-soundrate";
    args[argc++] = "48000";
    args[argc++] = "-sounddev";
    args[argc++] = "alsa";
    args[argc++] = "-sidengine";
    args[argc++] = "1";
    /* Default PRG autostart mode (AUTOSTART_PRG_MODE_DISK) builds a virtual
     * disk image on the fly, which fails in this headless bridge (no writable
     * scratch disk template configured). VFS mode injects the PRG directly
     * via virtual device traps instead, with no disk image needed. */
    args[argc++] = "-autostartprgmode";
    args[argc++] = "0";

    if (g_data_dir[0] != '\0') {
        args[argc++] = "-directory";
        args[argc++] = g_data_dir;
    }

    char media_buf[1024];
    if (media_path != NULL && media_path[0] != '\0') {
        snprintf(media_buf, sizeof(media_buf), "%s", media_path);
        switch (media_type) {
            case 0: /* PRG */
                /* VFS-mode PRG injection (AutostartPrgMode=0 above) is
                 * incompatible with true drive emulation on unit 8 ("Error -
                 * True drive emulation is still enabled" -> LOAD silently
                 * fails to find the injected file). Turn it off for this
                 * unit; DISK/TAPE media below want true drive emulation and
                 * are unaffected. */
                args[argc++] = "+drive8truedrive";
                args[argc++] = "-autostart";
                args[argc++] = media_buf;
                break;
            case 1: /* DISK */
                /* Say what the drive IS before attaching anything to it.
                 *
                 * Without this, autostart finds unit 8 is not a 1541, tries
                 * to change it, and VICE answers "Failed to set drive type" --
                 * after which device 8 does not exist and every .d64 dies on
                 * ?DEVICE NOT PRESENT. Tapes and PRGs were unaffected because
                 * neither needs a drive at all, which is exactly the pattern
                 * that was observed.
                 *
                 * Set on the command line rather than as a resource
                 * afterwards, so the drive is a 1541 before autostart ever
                 * inspects it. Its ROM is present (the log shows no "1541 ROM
                 * image not found" among the errors for every other drive
                 * type), so the type is accepted here. */
                args[argc++] = "-drive8type";
                args[argc++] = "1541";
                args[argc++] = "-8";
                args[argc++] = media_buf;
                args[argc++] = "-autostart";
                args[argc++] = media_buf;
                break;
            case 2: /* TAPE */
                args[argc++] = "-1";
                args[argc++] = media_buf;
                args[argc++] = "-autostart";
                args[argc++] = media_buf;
                break;
            default:
                args[argc++] = "-autostart";
                args[argc++] = media_buf;
                break;
        }
    }
    (void)command_line;

    LOGI("vice_core_start media_type=%d media=%s argc=%d", media_type,
         media_path ? media_path : "(none)", argc);
    start_core_thread((char **)args, argc);
    return 0;
}

/* Latches the machine's own idea of true drive emulation the first time it
 * is asked for, i.e. before any media swap has touched it. */
static void remember_cold_start_tde(void) {
    static bool captured = false;
    if (captured) return;
    captured = true;
    int tde = 1;
    if (resources_get_int_sprintf("Drive%dTrueEmulation", &tde, 8) == 0) {
        g_cold_start_tde = tde;
    }
    int type = -1, fsdev = -1;
    resources_get_int_sprintf("Drive%dType", &type, 8);
    resources_get_int_sprintf("FileSystemDevice%d", &fsdev, 8);
    LOGI("cold-start drive 8: truedrive=%d type=%d fsdevice=%d rom1541=%d",
         g_cold_start_tde, type, fsdev, drive_check_type(1541, 0));
}

void vice_core_stop(void) {
    LOGI("vice_core_stop requested");
    if (atomic_load_explicit(&g_core_running, memory_order_acquire)) {
        machine_trigger_reset(MACHINE_RESET_MODE_POWER_CYCLE);
    }
}

int32_t vice_core_is_running(void) {
    return atomic_load_explicit(&g_core_running, memory_order_acquire) ? 1 : 0;
}

void vice_core_set_paused(int32_t paused) {
    const bool next = paused != 0;
    const bool previous = atomic_exchange_explicit(&g_emulation_paused, next, memory_order_acq_rel);
    if (previous == next) {
        return;
    }
    LOGI("pause request=%d", next ? 1 : 0);
    if (!next) {
        pthread_mutex_lock(&g_pause_mutex);
        pthread_cond_broadcast(&g_pause_cv);
        pthread_mutex_unlock(&g_pause_mutex);
    }
}

void vice_core_key_event(int32_t key, int32_t pressed) {
    if (!atomic_load_explicit(&g_core_running, memory_order_acquire)) {
        return;
    }
    matrix_key_t mapped;
    if (c64_matrix_key((int)key, &mapped)) {
        keyboard_set_keyarr_any(mapped.row, mapped.column, pressed ? 1 : 0);
    }
}

void vice_core_matrix_key_event(int32_t row, int32_t column, int32_t pressed) {
    if (!atomic_load_explicit(&g_core_running, memory_order_acquire)) {
        return;
    }
    keyboard_set_keyarr_any((int)row, (int)column, pressed ? 1 : 0);
}

void vice_core_joystick(int32_t port, int32_t mask) {
    pthread_mutex_lock(&g_mutex);
    g_joystick_port = (int)port;
    g_joystick_mask = (int)mask;
    const uint16_t vice_mask = vice_joystick_mask(g_joystick_mask);
    joystick_set_value_absolute(vice_joystick_port(g_joystick_port), vice_mask);
    pthread_mutex_unlock(&g_mutex);
}

int32_t vice_core_attach_disk(const char *path) {
    if (path == NULL) {
        return -1;
    }
    const int result = file_system_attach_disk(8, 0, path);
    LOGI("attach_disk path=%s result=%d", path, result);
    return result;
}

int32_t vice_core_attach_tape(const char *path) {
    if (path == NULL) {
        return -1;
    }
    const int result = tape_image_attach(1, path);
    LOGI("attach_tape path=%s result=%d", path, result);
    return result;
}

const uint32_t *vice_core_get_framebuffer(int32_t *out_width, int32_t *out_height) {
    pthread_mutex_lock(&g_frame_mutex);
    if (out_width != NULL) *out_width = g_frame_width;
    if (out_height != NULL) *out_height = g_frame_height;
    const uint32_t *buf = g_frame_buffer;
    pthread_mutex_unlock(&g_frame_mutex);
    return buf;
}

/* Block until the core has completed `frames` further screen refreshes, or
 * until `timeout_ms` elapses (a paused or wedged core never gets there, and
 * must not hang the caller). Returns true if the frames arrived. */
static bool wait_for_fresh_frames(int frames, int timeout_ms) {
    const int start = atomic_load_explicit(&g_refresh_count, memory_order_acquire);
    for (int waited = 0; waited < timeout_ms; waited += 5) {
        if (atomic_load_explicit(&g_refresh_count, memory_order_acquire) - start >= frames) {
            return true;
        }
        struct timespec ts = { .tv_sec = 0, .tv_nsec = 5 * 1000 * 1000L };
        nanosleep(&ts, NULL);
    }
    LOGW("timed out waiting for %d fresh frames", frames);
    return false;
}

/* Queue a snapshot op for the core thread and block until it reports back.
 * Returns VICE's own result (0 = ok, <0 = failed), -1 if the core isn't
 * running, or -2 on timeout. */
static int32_t submit_snapshot_request(int op, const char *path) {
    if (path == NULL || path[0] == '\0') {
        return -1;
    }
    if (!atomic_load_explicit(&g_core_running, memory_order_acquire)) {
        LOGW("snapshot request rejected: core not running");
        return -1;
    }
    if (atomic_load_explicit(&g_snapshot_op, memory_order_acquire) != SNAPSHOT_OP_NONE ||
        atomic_load_explicit(&g_snapshot_trap_armed, memory_order_acquire)) {
        LOGW("snapshot request rejected: another snapshot op is in flight");
        return -1;
    }

    pthread_mutex_lock(&g_snapshot_mutex);
    snprintf(g_pending_snapshot_path, sizeof(g_pending_snapshot_path), "%s", path);
    g_snapshot_result = -1;
    g_snapshot_complete = false;
    g_snapshot_seq++;
    atomic_store_explicit(&g_snapshot_op, op, memory_order_release);
    nudge_core_thread();

    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += 10;

    int wait_result = 0;
    while (!g_snapshot_complete && wait_result == 0) {
        wait_result = pthread_cond_timedwait(&g_snapshot_cv, &g_snapshot_mutex, &deadline);
    }
    if (!g_snapshot_complete) {
        atomic_store_explicit(&g_snapshot_op, SNAPSHOT_OP_NONE, memory_order_release);
        pthread_mutex_unlock(&g_snapshot_mutex);
        LOGE("snapshot request timed out (op=%d path=%s)", op, path);
        return VICE_SNAPSHOT_TIMEOUT;
    }
    const int result = g_snapshot_result;
    pthread_mutex_unlock(&g_snapshot_mutex);

    /* A successful restore has rewound the machine, but the framebuffer still
     * holds whatever was last drawn -- the picture the user was looking at
     * before, or a frame drawn half either side of the restore. Anyone who
     * screenshots or renders immediately after this call (the test harness
     * and the Flutter thumbnail path both do) would capture that, and read it
     * as "the restore did nothing". Wait for two complete refreshes so the
     * caller is handed a frame the restored machine actually drew. */
    if (result == 0 && op == SNAPSHOT_OP_LOAD) {
        wait_for_fresh_frames(2, 2000);
    }
    return (int32_t)result;
}

int32_t vice_core_save_snapshot(const char *path) {
    return submit_snapshot_request(SNAPSHOT_OP_SAVE, path);
}

int32_t vice_core_load_snapshot(const char *path) {
    return submit_snapshot_request(SNAPSHOT_OP_LOAD, path);
}

int32_t vice_core_can_snapshot(void) {
    if (!atomic_load_explicit(&g_core_running, memory_order_acquire)) {
        return -1;
    }
    /* Reading the attached image's type is a plain pointer/int read of state
     * only the core thread writes (at attach time), so it does not need the
     * trap round-trip that touching machine state does. */
    return media_is_snapshottable() ? 1 : 0;
}

int32_t vice_core_get_audio_level(void) {
    return audio_backend_get_level();
}

/* ---------------------------------------------------------------------- */
/* Tape + drive activity, for the loading indicators                       */
/*                                                                         */
/* VICE reports load progress by calling into the UI's status bar. The     */
/* headless arch supplies these as empty stubs, so wrapping them is the    */
/* only place the information exists -- there is no "ask the datasette     */
/* where it is" entry point to poll instead.                               */
/*                                                                         */
/* Each wrapper stores the latest value and defers to the real (empty)     */
/* stub, so nothing about VICE's own behaviour changes. Read from the UI   */
/* thread while VICE writes from the emulation thread, hence the atomics.  */
/* ---------------------------------------------------------------------- */

static atomic_int g_tape_counter = 0;
static atomic_int g_tape_motor = 0;
static atomic_int g_tape_control = 0;
static atomic_int g_drive_half_track = 0;
static atomic_int g_drive_led = 0;

extern void __real_ui_display_tape_counter(int port, int counter);
extern void __wrap_ui_display_tape_counter(int port, int counter) {
    atomic_store_explicit(&g_tape_counter, counter, memory_order_relaxed);
    __real_ui_display_tape_counter(port, counter);
}

extern void __real_ui_display_tape_motor_status(int port, int motor);
extern void __wrap_ui_display_tape_motor_status(int port, int motor) {
    atomic_store_explicit(&g_tape_motor, motor, memory_order_relaxed);
    __real_ui_display_tape_motor_status(port, motor);
}

extern void __real_ui_display_tape_control_status(int port, int control);
extern void __wrap_ui_display_tape_control_status(int port, int control) {
    atomic_store_explicit(&g_tape_control, control, memory_order_relaxed);
    __real_ui_display_tape_control_status(port, control);
}

extern void __real_ui_display_drive_track(unsigned int drive_number,
                                          unsigned int drive_base,
                                          unsigned int half_track_number,
                                          unsigned int drive_side);
extern void __wrap_ui_display_drive_track(unsigned int drive_number,
                                          unsigned int drive_base,
                                          unsigned int half_track_number,
                                          unsigned int drive_side) {
    /* Unit 8 only: the app attaches a single disk, and reporting a second
     * unit's head position in the same indicator would just be confusing. */
    if (drive_number == 0) {
        atomic_store_explicit(&g_drive_half_track, (int)half_track_number,
                              memory_order_relaxed);
    }
    __real_ui_display_drive_track(drive_number, drive_base, half_track_number,
                                  drive_side);
}

extern void __real_ui_display_drive_led(unsigned int drive_number,
                                        unsigned int drive_base,
                                        unsigned int pwm1,
                                        unsigned int led_pwm2);
extern void __wrap_ui_display_drive_led(unsigned int drive_number,
                                        unsigned int drive_base,
                                        unsigned int pwm1,
                                        unsigned int led_pwm2) {
    if (drive_number == 0) {
        /* pwm1 is 0..1000 intensity; the indicator only needs "is it busy",
         * and anything above a flicker counts. */
        atomic_store_explicit(&g_drive_led, (int)pwm1, memory_order_relaxed);
    }
    __real_ui_display_drive_led(drive_number, drive_base, pwm1, led_pwm2);
}

int32_t vice_core_get_tape_counter(void) {
    return atomic_load_explicit(&g_tape_counter, memory_order_relaxed);
}

int32_t vice_core_get_tape_motor(void) {
    return atomic_load_explicit(&g_tape_motor, memory_order_relaxed);
}

int32_t vice_core_get_tape_control(void) {
    return atomic_load_explicit(&g_tape_control, memory_order_relaxed);
}

int32_t vice_core_get_drive_half_track(void) {
    return atomic_load_explicit(&g_drive_half_track, memory_order_relaxed);
}

int32_t vice_core_get_drive_led(void) {
    return atomic_load_explicit(&g_drive_led, memory_order_relaxed);
}

int32_t vice_core_get_fps(void) {
    return atomic_load_explicit(&g_current_fps, memory_order_acquire);
}
