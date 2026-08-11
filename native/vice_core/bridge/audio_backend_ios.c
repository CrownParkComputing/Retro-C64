/*
 * audio_backend_ios.c - CoreAudio (RemoteIO AudioUnit) sound backend for the
 * plain-C VICE bridges (game core and vsid) on iOS. Satisfies the same
 * audio_backend.h interface as the Linux audio_backend.c (ALSA) and the
 * Android audio_backend_android.c (AAudio).
 *
 * The ring buffer, the 80ms prebuffer gate, the ramp-to-zero underrun fill
 * and the smoothed peak level are all deliberately identical to the Android
 * backend -- only the output device differs. VICE's sound thread is the
 * single producer (audio_backend_write); the single consumer is CoreAudio's
 * own realtime render thread, which calls render_callback() below.
 *
 * The render callback runs on a realtime thread: no allocation, no locks and
 * no logging on the hot path beyond the same bounded atomic counters the
 * Android backend uses.
 *
 * The audio *session* (category, activation) is deliberately NOT set here.
 * AVAudioSession is an Objective-C API owned by the app, and Flutter plugins
 * touch it too; the Runner configures it once at startup (see
 * ios/Runner/AppDelegate.swift). Without that, a RemoteIO unit still plays,
 * but under the default SoloAmbient category it obeys the silent switch.
 * Restarting the output unit after an interruption, on the other hand, IS
 * this file's job -- see the interruption section below.
 */
#include "audio_backend.h"

#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <os/log.h>

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define LOGI(...) os_log_info(OS_LOG_DEFAULT, "AudioBackendIOS: " __VA_ARGS__)
#define LOGW(...) os_log(OS_LOG_DEFAULT, "AudioBackendIOS: " __VA_ARGS__)
#define LOGE(...) os_log_error(OS_LOG_DEFAULT, "AudioBackendIOS: " __VA_ARGS__)

#define AUDIO_RING_MILLIS 500
#define AUDIO_PREBUFFER_MILLIS 80

/* ---------------------------------------------------------------------- */
/* Ring buffer (single producer = VICE sound thread, single consumer =    */
/* the CoreAudio render callback thread).                                 */
/* ---------------------------------------------------------------------- */

static int16_t *g_ring = NULL;
static atomic_int g_ring_capacity_frames = 0;
static int g_channels = 2;
static int g_rate = 48000;

static atomic_uint_least64_t g_read_frame = 0;
static atomic_uint_least64_t g_write_frame = 0;
static atomic_bool g_prefilled = false;
static atomic_int g_prebuffer_frames = 0;
static int16_t g_last_output[2] = {0, 0};

static atomic_int g_audio_level = 0;
static atomic_int g_drop_log_count = 0;
static atomic_int g_xrun_log_count = 0;

static AudioUnit g_unit = NULL;
static atomic_bool g_running = false;

static void ring_reset(void) {
    atomic_store_explicit(&g_read_frame, 0, memory_order_release);
    atomic_store_explicit(&g_write_frame, 0, memory_order_release);
    atomic_store_explicit(&g_prefilled, false, memory_order_release);
    g_last_output[0] = 0;
    g_last_output[1] = 0;
}

static int32_t ring_available_frames(void) {
    const uint64_t r = atomic_load_explicit(&g_read_frame, memory_order_acquire);
    const uint64_t w = atomic_load_explicit(&g_write_frame, memory_order_acquire);
    const int32_t capacity = atomic_load_explicit(&g_ring_capacity_frames, memory_order_acquire);
    if (w <= r || capacity <= 0) return 0;
    const uint64_t avail = w - r;
    return (int32_t)(avail < (uint64_t)capacity ? avail : (uint64_t)capacity);
}

static void ring_push(const int16_t *input, int32_t frames) {
    const int32_t capacity = atomic_load_explicit(&g_ring_capacity_frames, memory_order_acquire);
    const int channels = g_channels;
    if (input == NULL || frames <= 0 || g_ring == NULL || capacity <= 0 || channels <= 0) return;

    if (frames > capacity) {
        input += (size_t)(frames - capacity) * (size_t)channels;
        frames = capacity;
    }

    const uint64_t r = atomic_load_explicit(&g_read_frame, memory_order_acquire);
    const uint64_t w = atomic_load_explicit(&g_write_frame, memory_order_relaxed);
    const uint64_t avail = w > r ? w - r : 0;
    if (avail + (uint64_t)frames > (uint64_t)capacity) {
        const uint64_t keep = (uint64_t)(capacity - frames);
        atomic_store_explicit(&g_read_frame, w > keep ? w - keep : w, memory_order_release);
        int drop_log = atomic_fetch_add(&g_drop_log_count, 1);
        if (drop_log < 8) {
            LOGW("ring full; dropping old frames available=%llu incoming=%d capacity=%d",
                 (unsigned long long)avail, frames, capacity);
        }
    }

    int32_t remaining = frames;
    uint64_t write_cursor = w;
    const int16_t *src = input;
    while (remaining > 0) {
        const int32_t ring_frame = (int32_t)(write_cursor % (uint64_t)capacity);
        const int32_t chunk = remaining < (capacity - ring_frame) ? remaining : (capacity - ring_frame);
        memcpy(g_ring + (size_t)ring_frame * channels, src, (size_t)chunk * channels * sizeof(int16_t));
        remaining -= chunk;
        write_cursor += chunk;
        src += (size_t)chunk * channels;
    }
    atomic_store_explicit(&g_write_frame, w + (uint64_t)frames, memory_order_release);
}

/* Linear ramp-to-zero from the last real sample instead of a hard
 * discontinuity while waiting for the ring to (re)fill. */
static void fill_from_last_sample(int16_t *output, int32_t frames, int channels) {
    if (output == NULL || frames <= 0 || channels <= 0) return;
    const int16_t left = g_last_output[0];
    const int16_t right = channels > 1 ? g_last_output[1] : left;
    for (int32_t frame = 0; frame < frames; frame++) {
        const int32_t scale = frames - frame;
        output[(size_t)frame * channels] = (int16_t)(((int32_t)left * scale) / frames);
        if (channels > 1) {
            output[(size_t)frame * channels + 1] = (int16_t)(((int32_t)right * scale) / frames);
        }
    }
    g_last_output[0] = 0;
    g_last_output[1] = 0;
}

static OSStatus render_callback(void *user_data,
                                AudioUnitRenderActionFlags *action_flags,
                                const AudioTimeStamp *timestamp,
                                UInt32 bus,
                                UInt32 num_frames,
                                AudioBufferList *data) {
    (void)user_data;
    (void)timestamp;
    (void)bus;

    /* Interleaved PCM: RemoteIO hands us exactly one buffer. */
    int16_t *output = (data != NULL && data->mNumberBuffers > 0)
            ? (int16_t *)data->mBuffers[0].mData : NULL;
    const int channels = g_channels;
    const int32_t capacity = atomic_load_explicit(&g_ring_capacity_frames, memory_order_acquire);
    if (output == NULL || num_frames == 0 || channels <= 0 || capacity <= 0 || g_ring == NULL) {
        if (output != NULL && data->mBuffers[0].mDataByteSize > 0) {
            memset(output, 0, data->mBuffers[0].mDataByteSize);
            if (action_flags != NULL) *action_flags |= kAudioUnitRenderAction_OutputIsSilence;
        }
        return noErr;
    }

    int32_t available = ring_available_frames();
    const int32_t configured_prebuffer = atomic_load_explicit(&g_prebuffer_frames, memory_order_acquire);
    int32_t prebuffer = configured_prebuffer > 0 ? configured_prebuffer : 2048;
    if (prebuffer < 1024) prebuffer = 1024;
    if (prebuffer > capacity / 3) prebuffer = capacity / 3;

    if (!atomic_load_explicit(&g_prefilled, memory_order_acquire) && available < prebuffer) {
        fill_from_last_sample(output, (int32_t)num_frames, channels);
        return noErr;
    }
    atomic_store_explicit(&g_prefilled, true, memory_order_release);

    uint64_t read = atomic_load_explicit(&g_read_frame, memory_order_relaxed);
    const uint64_t write = atomic_load_explicit(&g_write_frame, memory_order_acquire);
    if (write < read) {
        read = write;
        atomic_store_explicit(&g_read_frame, read, memory_order_release);
        available = 0;
    } else {
        const uint64_t a = write - read;
        available = (int32_t)(a < (uint64_t)capacity ? a : (uint64_t)capacity);
    }

    const int32_t frames_to_read = (int32_t)num_frames < available ? (int32_t)num_frames : available;
    int32_t remaining = frames_to_read;
    int16_t *dest = output;
    uint64_t read_cursor = read;
    while (remaining > 0) {
        const int32_t ring_frame = (int32_t)(read_cursor % (uint64_t)capacity);
        const int32_t chunk = remaining < (capacity - ring_frame) ? remaining : (capacity - ring_frame);
        memcpy(dest, g_ring + (size_t)ring_frame * channels, (size_t)chunk * channels * sizeof(int16_t));
        remaining -= chunk;
        read_cursor += chunk;
        dest += (size_t)chunk * channels;
    }

    if (frames_to_read > 0) {
        const int16_t *last = output + (size_t)(frames_to_read - 1) * channels;
        g_last_output[0] = last[0];
        g_last_output[1] = channels > 1 ? last[1] : last[0];
    }

    if (frames_to_read < (int32_t)num_frames) {
        fill_from_last_sample(dest, (int32_t)num_frames - frames_to_read, channels);
        int xrun_log = atomic_fetch_add(&g_xrun_log_count, 1);
        if (xrun_log < 8) {
            LOGW("render underrun read=%d requested=%u available=%d",
                 frames_to_read, (unsigned)num_frames, available);
        }
    }

    atomic_store_explicit(&g_read_frame, read + (uint64_t)frames_to_read, memory_order_release);
    return noErr;
}

/* ---------------------------------------------------------------------- */
/* Interruptions                                                          */
/*                                                                        */
/* A phone call, Siri, or another app taking the session stops the output */
/* unit, and iOS does not restart it: without this, one incoming call     */
/* would leave the emulator silent until the core is torn down and        */
/* rebuilt. The session itself is the app's (AppDelegate.swift), but the  */
/* unit is ours, so the restart has to happen here.                       */
/*                                                                        */
/* AVAudioSession is Objective-C, but its notifications are posted to the */
/* same notification centre CFNotificationCenterGetLocalCenter() observes,*/
/* and the userInfo keys are documented constants -- so a plain-C backend */
/* can listen without dragging Objective-C into this file.                */
/* ---------------------------------------------------------------------- */

#define IOS_INTERRUPTION_TYPE_ENDED 1

/* Identifies *this* backend to the notification centre. The game core and
 * the vsid core each link their own copy of this file, so each gets its own
 * address here; registering both as NULL would make one core's teardown
 * unregister the other core's observer. */
static const char g_observer_token = 0;

static void interruption_callback(CFNotificationCenterRef center,
                                  void *observer,
                                  CFNotificationName name,
                                  const void *object,
                                  CFDictionaryRef user_info) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;

    if (user_info == NULL) return;
    CFNumberRef type = CFDictionaryGetValue(user_info,
                                            CFSTR("AVAudioSessionInterruptionType"));
    if (type == NULL) return;
    int value = -1;
    if (!CFNumberGetValue(type, kCFNumberIntType, &value)) return;
    if (value != IOS_INTERRUPTION_TYPE_ENDED) return;

    /* Only if we were meant to be playing: an interruption that ends while
     * the core is deliberately paused must stay silent. */
    if (g_unit == NULL || !atomic_load_explicit(&g_running, memory_order_acquire)) return;

    ring_reset();
    if (AudioOutputUnitStart(g_unit) == noErr) {
        LOGI("restarted after interruption");
        return;
    }

    /* The unit will not start until the session is active again, and that is
     * the app's call (AppDelegate.swift), made from its own observer of this
     * same notification. Observers run in registration order, and this one
     * registers later -- when a core first opens audio -- so in practice the
     * session is already back. The retry is for when it isn't. */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        if (g_unit == NULL || !atomic_load_explicit(&g_running, memory_order_acquire)) return;
        const OSStatus retry = AudioOutputUnitStart(g_unit);
        if (retry != noErr) {
            LOGE("restart after interruption failed: %d", (int)retry);
        } else {
            LOGI("restarted after interruption (retry)");
        }
    });
}

static void observe_interruptions(bool observe) {
    static bool observing = false;
    if (observe == observing) return;
    CFNotificationCenterRef center = CFNotificationCenterGetLocalCenter();
    if (observe) {
        CFNotificationCenterAddObserver(
                center, &g_observer_token, interruption_callback,
                CFSTR("AVAudioSessionInterruptionNotification"), NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
    } else {
        CFNotificationCenterRemoveObserver(
                center, &g_observer_token,
                CFSTR("AVAudioSessionInterruptionNotification"), NULL);
    }
    observing = observe;
}

/* ---------------------------------------------------------------------- */
/* Public sound_device_t-shaped API                                       */
/* ---------------------------------------------------------------------- */

static void teardown_stream(void) {
    observe_interruptions(false);
    if (g_unit != NULL) {
        if (atomic_exchange_explicit(&g_running, false, memory_order_acq_rel)) {
            AudioOutputUnitStop(g_unit);
        }
        AudioUnitUninitialize(g_unit);
        AudioComponentInstanceDispose(g_unit);
        g_unit = NULL;
    }
    /* Only safe after the unit is disposed: the render thread is the other
     * user of g_ring and disposing the unit joins it. */
    atomic_store_explicit(&g_ring_capacity_frames, 0, memory_order_release);
    free(g_ring);
    g_ring = NULL;
}

int audio_backend_init(const char *param, int *speed, int *fragsize, int *fragnr, int *channels) {
    (void)param;
    (void)fragsize;
    (void)fragnr;
    teardown_stream();
    atomic_store_explicit(&g_audio_level, 0, memory_order_relaxed);
    atomic_store_explicit(&g_drop_log_count, 0, memory_order_relaxed);
    atomic_store_explicit(&g_xrun_log_count, 0, memory_order_relaxed);

    g_channels = (channels != NULL && *channels > 1) ? 2 : 1;
    g_rate = (speed != NULL && *speed > 0) ? *speed : 48000;

    AudioComponentDescription desc = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_RemoteIO,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0,
    };
    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    if (component == NULL) {
        LOGE("no RemoteIO audio component");
        return 1;
    }

    OSStatus status = AudioComponentInstanceNew(component, &g_unit);
    if (status != noErr || g_unit == NULL) {
        LOGE("AudioComponentInstanceNew failed: %d", (int)status);
        g_unit = NULL;
        return 1;
    }

    /* Bus 0 is hardware output; its *input* scope is what we feed. */
    AudioStreamBasicDescription format = {
        .mSampleRate = (Float64)g_rate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mFramesPerPacket = 1,
        .mChannelsPerFrame = (UInt32)g_channels,
        .mBitsPerChannel = 16,
        .mBytesPerFrame = (UInt32)(2 * g_channels),
        .mBytesPerPacket = (UInt32)(2 * g_channels),
    };
    status = AudioUnitSetProperty(g_unit, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input, 0, &format, sizeof(format));
    if (status != noErr) {
        LOGE("set stream format failed: %d", (int)status);
        teardown_stream();
        return 1;
    }

    AURenderCallbackStruct callback = {
        .inputProc = render_callback,
        .inputProcRefCon = NULL,
    };
    status = AudioUnitSetProperty(g_unit, kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input, 0, &callback, sizeof(callback));
    if (status != noErr) {
        LOGE("set render callback failed: %d", (int)status);
        teardown_stream();
        return 1;
    }

    status = AudioUnitInitialize(g_unit);
    if (status != noErr) {
        LOGE("AudioUnitInitialize failed: %d", (int)status);
        teardown_stream();
        return 1;
    }

    /* CoreAudio may resample for us, but VICE wants to know what it is
     * actually producing into: report back whatever the unit accepted. */
    AudioStreamBasicDescription actual = format;
    UInt32 actual_size = sizeof(actual);
    if (AudioUnitGetProperty(g_unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0, &actual, &actual_size) == noErr) {
        if (actual.mSampleRate > 0) g_rate = (int)actual.mSampleRate;
        if (actual.mChannelsPerFrame > 0) g_channels = (int)actual.mChannelsPerFrame;
    }
    if (speed != NULL) *speed = g_rate;
    if (channels != NULL) *channels = g_channels;

    int32_t ring_capacity = g_rate * AUDIO_RING_MILLIS / 1000;
    if (ring_capacity < 8192) ring_capacity = 8192;
    g_ring = calloc((size_t)ring_capacity * (size_t)g_channels, sizeof(int16_t));
    if (g_ring == NULL) {
        LOGE("ring buffer allocation failed");
        teardown_stream();
        return 1;
    }
    atomic_store_explicit(&g_ring_capacity_frames, ring_capacity, memory_order_release);
    int32_t prebuffer = g_rate * AUDIO_PREBUFFER_MILLIS / 1000;
    if (prebuffer < 2048) prebuffer = 2048;
    atomic_store_explicit(&g_prebuffer_frames, prebuffer, memory_order_release);
    ring_reset();

    status = AudioOutputUnitStart(g_unit);
    if (status != noErr) {
        LOGE("AudioOutputUnitStart failed: %d", (int)status);
        teardown_stream();
        return 1;
    }
    atomic_store_explicit(&g_running, true, memory_order_release);
    observe_interruptions(true);

    LOGI("RemoteIO opened rate=%d channels=%d ring=%d prebuffer=%d",
         g_rate, g_channels, ring_capacity, prebuffer);
    return 0;
}

int audio_backend_write(int16_t *pbuf, size_t nr) {
    if (pbuf == NULL || nr == 0 || g_channels <= 0 || g_unit == NULL) return 0;
    const int32_t frames = (int32_t)(nr / (size_t)g_channels);
    if (frames > 0) {
        ring_push(pbuf, frames);
    }

    int32_t peak = 0;
    for (size_t i = 0; i < nr; i++) {
        int32_t v = pbuf[i];
        if (v < 0) v = -v;
        if (v > peak) peak = v;
    }
    const int32_t target = (int32_t)(((int64_t)peak * 100) / 32768);
    const int32_t cur = atomic_load_explicit(&g_audio_level, memory_order_relaxed);
    atomic_store_explicit(&g_audio_level, (cur * 3 + target) / 4, memory_order_relaxed);
    return 0;
}

void audio_backend_close(void) {
    teardown_stream();
    atomic_store_explicit(&g_audio_level, 0, memory_order_relaxed);
}

int audio_backend_suspend(void) {
    if (g_unit != NULL && atomic_exchange_explicit(&g_running, false, memory_order_acq_rel)) {
        AudioOutputUnitStop(g_unit);
    }
    ring_reset();
    atomic_store_explicit(&g_audio_level, 0, memory_order_relaxed);
    return 0;
}

int audio_backend_resume(void) {
    ring_reset();
    if (g_unit != NULL && !atomic_load_explicit(&g_running, memory_order_acquire)) {
        const OSStatus status = AudioOutputUnitStart(g_unit);
        if (status != noErr) {
            LOGE("AudioOutputUnitStart (resume) failed: %d", (int)status);
            return 1;
        }
        atomic_store_explicit(&g_running, true, memory_order_release);
    }
    return 0;
}

int32_t audio_backend_get_level(void) {
    return atomic_load_explicit(&g_audio_level, memory_order_relaxed);
}
