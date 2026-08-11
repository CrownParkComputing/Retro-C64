/*
 * audio_backend.h - Shared ALSA + optional WAV-capture sound backend for the
 * plain-C VICE bridges (game core and vsid). Mirrors the ring-buffer /
 * prebuffer-gate shape of VICEAndroid's AAudio backend
 * (vice_android_bridge.cpp android_sound_write/android_sound_init) but talks
 * to ALSA instead of AAudio, and can additionally (or instead) redirect the
 * PCM stream to a .wav file for headless verification.
 *
 * Not thread-safe to call concurrently from multiple producer threads; VICE
 * only ever calls the sound_device_t callbacks from its own single sound
 * thread, which is the only producer here. A single background consumer
 * thread drains the ring buffer into ALSA.
 */
#ifndef VICE_MULTIPLATFORM_AUDIO_BACKEND_H
#define VICE_MULTIPLATFORM_AUDIO_BACKEND_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* sound_device_t-shaped callbacks; wire these directly into a
 * static const sound_device_t in each bridge. */
int audio_backend_init(const char *param, int *speed, int *fragsize, int *fragnr, int *channels);
int audio_backend_write(int16_t *pbuf, size_t nr);
void audio_backend_close(void);
int audio_backend_suspend(void);
int audio_backend_resume(void);

/* Smoothed 0..100 peak level, same semaphore-free EQ level the dummy backend
 * used to compute, now computed from real PCM on every write. */
int32_t audio_backend_get_level(void);

#ifdef __cplusplus
}
#endif

#endif /* VICE_MULTIPLATFORM_AUDIO_BACKEND_H */
