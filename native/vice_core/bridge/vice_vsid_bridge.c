/*
 * vice_vsid_bridge.c - Plain-C-ABI bridge around the VICE vsid headless core.
 *
 * Non-JNI port of vice_vsid_bridge.cpp (see vice_vsid_bridge.h for details).
 * Shares audio_backend.c (ALSA + optional WAV capture) with vice_bridge.c;
 * vsid has no video canvas so this file needs none of vice_bridge.c's
 * video_canvas_* wraps.
 */

#include <errno.h>
#include <pthread.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "machine.h"
#include "psid.h"
#include "resources.h"
#include "sound.h"
#include "vsync.h"

#include "audio_backend.h"
#include "vice_vsid_bridge.h"

extern int main_program(int argc, char **argv);

#define TAG "VICEVsidBridge"

#ifdef __ANDROID__
/* See vice_bridge.c: Android discards stdout/stderr, so these have to go
 * through the platform logger to be visible to `adb logcat`. */
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
/* Global state (mirrors vice_bridge.c's statics)                         */
/* ---------------------------------------------------------------------- */

static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_pause_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_pause_cv = PTHREAD_COND_INITIALIZER;
static pthread_mutex_t g_swap_mutex = PTHREAD_MUTEX_INITIALIZER;

static char g_data_dir[1024];

static atomic_bool g_core_started = false;
static atomic_bool g_core_running = false;
static atomic_bool g_emulation_paused = false;

/* Pending hot-swap request: set by vice_vsid_launch() (called from whatever
 * thread the Dart FFI/UI call lands on) and consumed by the VICE core's OWN
 * mainloop thread (via the vsync hook below). VICE's machine/CPU state is
 * not safe to touch from a thread other than the one running its mainloop,
 * so the calling thread only ever writes this mailbox -- it never calls
 * machine_autodetect_psid()/machine_play_psid() itself. A newer request
 * overwrites an older unconsumed one, which also coalesces rapid repeated
 * taps down to just the last-selected track instead of applying several
 * hot-swaps back-to-back. */
static char g_pending_swap_path[1024];
static atomic_bool g_swap_pending = false;

/* ---------------------------------------------------------------------- */
/* Environment prep (same XDG-dir dance as vice_bridge.c)                  */
/* ---------------------------------------------------------------------- */

static void ensure_dir(const char *path) {
    if (path == NULL || path[0] == '\0') return;
    if (mkdir(path, 0700) != 0 && errno != EEXIST) {
        LOGW("Could not create %s: errno=%d", path, errno);
    }
}

static void prepare_vice_environment(void) {
    if (g_data_dir[0] == '\0') return;
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
/* ALSA sound backend, same as vice_bridge.c                              */
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
    LOGI("Registering plain-C ALSA sound device (vsid)");
    return sound_register_device(&alsa_sound_device);
}

/* ---------------------------------------------------------------------- */
/* Startup-sequence --wrap= hooks (video_canvas_* omitted: vsid has none)  */
/* ---------------------------------------------------------------------- */

extern int __real_archdep_init(int *argc, char **argv);
/* The SID player runs the same VICE archdep code in the same host process as
 * vice_bridge.c, so it carries the identical hazard: archdep_vice_exit()
 * calls libc exit(), which runs __cxa_finalize across every loaded library
 * including libflutter.so and aborts the app. Contain it the same way --
 * unwind the player thread, never the process. See the long note in
 * vice_bridge.c's __wrap_archdep_vice_exit. */
static pthread_t g_core_tid;
static atomic_bool g_core_tid_valid = false;

extern void __real_archdep_vice_exit(int exit_code);
extern void __wrap_archdep_vice_exit(int exit_code) {
    LOGE("archdep_vice_exit(%d) intercepted in the SID player -- unwinding "
         "the player thread instead of killing the process", exit_code);
    atomic_store_explicit(&g_core_running, false, memory_order_release);
    if (atomic_load_explicit(&g_core_tid_valid, memory_order_acquire) &&
        pthread_equal(pthread_self(), g_core_tid)) {
        pthread_exit(NULL);
    }
    LOGE("archdep_vice_exit called off the player thread; returning instead");
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
    LOGI("stage init_main end result=%d", result);
    return result;
}

extern void __real_maincpu_mainloop(void);
extern void __wrap_maincpu_mainloop(void) {
    LOGI("stage maincpu_mainloop begin");
    __real_maincpu_mainloop();
    LOGE("stage maincpu_mainloop returned");
}

static void wait_while_emulation_paused(void) {
    if (!atomic_load_explicit(&g_emulation_paused, memory_order_acquire)) return;
    LOGI("pause gate entered");
    sound_suspend();
    vsync_suspend_speed_eval();

    pthread_mutex_lock(&g_pause_mutex);
    while (atomic_load_explicit(&g_emulation_paused, memory_order_acquire)) {
        pthread_cond_wait(&g_pause_cv, &g_pause_mutex);
    }
    pthread_mutex_unlock(&g_pause_mutex);

    sound_resume();
    vsync_suspend_speed_eval();
    LOGI("pause gate resumed");
}

/* Runs on the VICE core's own mainloop thread (called from the vsync hook
 * below, i.e. from inside maincpu_mainloop's call stack), so it is safe to
 * touch machine/CPU state here the same way VICE's own UI backends do (see
 * arch/gtk3/uivsidwindow.c's ui_vsid_window_load_psid(), which this mirrors
 * exactly: suspend speed eval, autodetect+load the new PSID, relocate its
 * player driver, select tune 0, then trigger a CPU reset so execution
 * actually jumps into the new driver -- machine_specific_reset() also calls
 * sid_reset(), which is what silences the previous tune's SID chip state
 * instead of leaving it layered under the new one). */
static void apply_pending_swap_if_any(void) {
    if (!atomic_load_explicit(&g_swap_pending, memory_order_acquire)) return;

    char path[sizeof(g_pending_swap_path)];
    pthread_mutex_lock(&g_swap_mutex);
    snprintf(path, sizeof(path), "%s", g_pending_swap_path);
    pthread_mutex_unlock(&g_swap_mutex);
    atomic_store_explicit(&g_swap_pending, false, memory_order_release);

    if (path[0] == '\0') return;

    LOGI("core thread applying pending hot-swap to: %s", path);
    vsync_suspend_speed_eval();
    if (machine_autodetect_psid(path) < 0) {
        LOGW("hot-swap: machine_autodetect_psid failed for %s", path);
        return;
    }
    psid_init_driver();
    machine_play_psid(0);
    machine_trigger_reset(MACHINE_RESET_MODE_RESET_CPU);
    LOGI("hot-swap applied: %s", path);
}

extern void __real_vsync_do_vsync(struct video_canvas_s *canvas);
extern void __wrap_vsync_do_vsync(struct video_canvas_s *canvas) {
    apply_pending_swap_if_any();
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

/* Lift the emulation thread above ordinary background work.
 *
 * VICE runs in-process beside Flutter's UI and raster threads; at equal
 * priority a busy launcher frame starves the audio producer and the sound
 * breaks up -- the exact failure Retro-Amiga's live release reports were
 * about, fixed there with the same call. -2 lifts this thread above default
 * work while leaving the platform's audio callback (higher still) alone.
 *
 * An app may do this to its own threads: Android raises RLIMIT_NICE for app
 * processes precisely so it can. Where it may not (an unprivileged desktop)
 * the call fails and the emulator runs exactly as it did.
 */
static void raise_emulation_thread_priority(void) {
#if defined(__linux__)
    errno = 0;
    if (setpriority(PRIO_PROCESS, (id_t)syscall(SYS_gettid), -2) != 0 &&
        errno != 0) {
        LOGW("core thread: could not raise priority (%s)", strerror(errno));
        return;
    }
    LOGI("core thread: priority raised to nice -2");
#endif
}

static void *core_thread_main(void *arg) {
    raise_emulation_thread_priority();
    core_thread_args_t *targs = (core_thread_args_t *)arg;
    g_core_tid = pthread_self();
    atomic_store_explicit(&g_core_tid_valid, true, memory_order_release);
    prepare_vice_environment();
    atomic_store_explicit(&g_core_running, true, memory_order_release);
    LOGI("Starting VICE (vsid) main_program argc=%d", targs->argc);

    /* Same double-free hazard/fix as vice_bridge.c's core_thread_main: give
     * VICE a disposable scratch copy of the pointer array. */
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
    LOGE("VICE vsid main_program returned %d", result);

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
/* Public C API (vice_vsid_bridge.h)                                       */
/* ---------------------------------------------------------------------- */

void vice_vsid_init(const char *rom_dir) {
    pthread_mutex_lock(&g_mutex);
    if (rom_dir != NULL) {
        snprintf(g_data_dir, sizeof(g_data_dir), "%s", rom_dir);
    } else {
        g_data_dir[0] = '\0';
    }
    LOGI("Initialized vsid bridge with rom/data dir: %s", g_data_dir);
    pthread_mutex_unlock(&g_mutex);
}

int32_t vice_vsid_launch(const char *media_path, const char *command_line) {
    (void)command_line;

    if (!atomic_exchange_explicit(&g_core_started, true, memory_order_acq_rel)) {
        const char *args[32];
        int argc = 0;
        args[argc++] = "vsid";
        args[argc++] = "-default";
        /* Not -verbose, for the same reason as the game core -- see the note
         * in vice_bridge.c. Both cores share one log file now, so verbose
         * output from either buries the other. */
        args[argc++] = "+logcolorize";
        if (g_data_dir[0] != '\0') {
            args[argc++] = "-directory";
            args[argc++] = g_data_dir;
        }
        args[argc++] = "-soundrate";
        args[argc++] = "48000";
        args[argc++] = "-soundbufsize";
        args[argc++] = "100";
        args[argc++] = "-soundfragsize";
        args[argc++] = "3";
        args[argc++] = "-soundoutput";
        args[argc++] = "2";
        args[argc++] = "-sounddev";
        args[argc++] = "alsa";
        args[argc++] = "-sidengine";
        args[argc++] = "1"; /* reSID */

        /* vsid treats the last orphan arg as the autostart .sid/.psid file. */
        if (media_path != NULL && media_path[0] != '\0') {
            args[argc++] = media_path;
        }

        LOGI("vice_vsid_launch (first start) media=%s argc=%d", media_path ? media_path : "(none)", argc);
        start_core_thread((char **)args, argc);
        return 0;
    }

    /* Already running: queue a hot-swap request for the core's OWN mainloop
     * thread to pick up (see apply_pending_swap_if_any()). Do NOT call
     * machine_autodetect_psid()/machine_play_psid() here -- this function
     * can be invoked from an arbitrary caller thread (the Dart FFI/UI
     * thread in the Flutter app), and VICE's machine/CPU state must only
     * ever be touched from the thread that's actually running its
     * mainloop. */
    if (atomic_load_explicit(&g_core_running, memory_order_acquire)) {
        if (media_path == NULL || media_path[0] == '\0') {
            LOGW("vice_vsid_launch: core already running and no media given, nothing to do");
            return -1;
        }
        LOGI("vice_vsid_launch: queuing hot-swap to new SID: %s", media_path);
        pthread_mutex_lock(&g_swap_mutex);
        snprintf(g_pending_swap_path, sizeof(g_pending_swap_path), "%s", media_path);
        pthread_mutex_unlock(&g_swap_mutex);
        atomic_store_explicit(&g_swap_pending, true, memory_order_release);
        return 0;
    }

    LOGW("vice_vsid_launch: core was started but is no longer running");
    return -1;
}

void vice_vsid_set_paused(int32_t paused) {
    const bool next = paused != 0;
    const bool previous = atomic_exchange_explicit(&g_emulation_paused, next, memory_order_acq_rel);
    if (previous == next) return;
    LOGI("pause request=%d", next ? 1 : 0);
    if (!next) {
        pthread_mutex_lock(&g_pause_mutex);
        pthread_cond_broadcast(&g_pause_cv);
        pthread_mutex_unlock(&g_pause_mutex);
    }
}

int32_t vice_vsid_is_running(void) {
    return atomic_load_explicit(&g_core_running, memory_order_acquire) ? 1 : 0;
}

int32_t vice_vsid_get_audio_level(void) {
    return audio_backend_get_level();
}

int32_t vice_vsid_get_fps(void) {
    return 0;
}
