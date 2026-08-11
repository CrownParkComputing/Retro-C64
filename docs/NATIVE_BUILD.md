# Native core build

The emulator itself is not written here. `libvicecore` (the x64sc game core)
and `libvicecore_vsid` (the SID player) are thin plain-C bridges in
`native/vice_core/bridge/` linked against **VICE**'s own compiled objects.

## The constraint CI can't get around

Both libraries link against a *pre-built* VICE object tree that lives outside
this repository:

```
~/AndroidStudioProjects/VICE-source/vice-3.10/
    build-android-arm64-headless/    # NDK cross-compiled, for Android
    build-linux-x64-headless/        # host compiled, for Linux
    build-ios-arm64-headless/        # Xcode cross-compiled, iOS device
    build-iossim-arm64-headless/     # iOS simulator, Apple silicon
    build-iossim-x86_64-headless/    # iOS simulator, Intel
```

Those are produced by running VICE's own `configure`/`make` with
`--enable-headlessui` (see `native/vice_core/linux/build-vice-linux-headless.sh`,
`native/vice_core/ios/build-vice-ios-headless.sh`, and, for Android, the NDK
toolchain flags in `native/vice_core/android/build.sh`). They are large,
machine-specific and not redistributable here, so **GitHub Actions cannot
rebuild the native cores**.

Consequences, reflected in `.github/workflows/build.yml`:

- **Android** — the arm64 `.so` files are **committed** under
  `flutter_app/android/app/src/main/jniLibs/arm64-v8a/`. CI consumes them and
  fails loudly if they're missing. Rebuild and re-commit them whenever
  `native/vice_core/bridge/*.c` changes.
- **Linux** — CI builds the Flutter bundle only. It ships *without*
  `libvicecore.so`, so the app will report "Failed to load libvicecore" until
  one is placed next to the executable. Build it locally with the CMake
  project in `native/vice_core/linux/`.
- **iOS** — the arm64 device libraries are **committed** under
  `flutter_app/ios/vicecore/iphoneos/`, same bargain as Android. The
  simulator slice is gitignored; build it locally before running on a
  simulator. Rebuild and re-commit the device slice whenever
  `native/vice_core/bridge/*.c` changes.

## Rebuilding after changing bridge code

```bash
# Linux
cd native/vice_core/linux/build && cmake .. && cmake --build . -j4

# Android arm64 -> flutter_app/android/app/src/main/jniLibs/arm64-v8a/
native/vice_core/android/build.sh

# iOS arm64 (device + simulator) -> flutter_app/ios/vicecore/<sdk>/
# Builds the VICE tree for each SDK on first run (~10 min each), then just
# relinks. `--sdk iphoneos` to do only the device slice.
native/vice_core/ios/build.sh
```

## What is different about iOS

Three constraints have no equivalent on Linux or Android, and each is worth
knowing before touching `native/vice_core/ios/`.

**Apple's linker has no `--wrap`.** The bridges intercept a dozen VICE
functions (`maincpu_mainloop`, `video_canvas_refresh`, ...) with GNU ld's
`-Wl,--wrap=`; `ld` on macOS answers `unknown options: --wrap`. So
`build-vice-ios-headless.sh` compiles the whole VICE tree with `-DX=__wrap_X`
— redirecting every *reference* — and then recompiles just the file that
*defines* each one with `-DX=__real_X`. That reproduces `--wrap` exactly,
including its subtlety that a call to X from inside X's own file is not
redirected. The script verifies the result with `nm` and fails loudly if a
`__wrap_` definition survives, which is what a missed defining file looks
like.

**Both cores share one binary.** On Android the game core and the SID player
are two `.so` files, each with its own private copy of VICE. iOS links both
into the app executable, where VICE's several thousand symbols would collide
head-on. `build.sh` therefore partially links (`ld -r`) each core into a
single object that exports *only* its own `vice_core_*` / `vice_vsid_*` API
and makes everything else a private extern. The two cores then coexist the
same way the two `.so` files do, and the build fails if either leaks a
non-API symbol.

**Nothing references the cores at link time.** Dart finds them at runtime via
`DynamicLibrary.process()`, so `flutter_app/ios/Flutter/VICECore.xcconfig`
has to both `-force_load` the archives and name every entry point with `-u`
so release dead-stripping keeps them. Add a function to a bridge header and
you must add it there too.

Audio goes through `bridge/audio_backend_ios.c`, a RemoteIO AudioUnit backend
with the same ring buffer and prebuffer gate as the ALSA and AAudio ones. The
audio *session* is the app's business, not the core's, and is configured in
`flutter_app/ios/Runner/AppDelegate.swift`.

## Tests

The native tests take media paths as arguments and are run against your own
local C64 files:

```bash
cd native/vice_core/linux/build
./vice_smoke_test <rom_dir>
./vice_swap_snapshot_test <rom_dir> "disk:/path/a.d64" "disk:/path/b.d64" out.vsf
./vice_joystick_port_test <rom_dir> "disk:/path/a.d64" 2 25
```

`<rom_dir>` must contain `C64/` (kernal, basic, chargen) and `DRIVES/` (the
1541 ROMs — without these, D64 autostart fails with `?DEVICE NOT PRESENT`).

Commercial game images are deliberately **not** committed (see `.gitignore`);
point the tests at your own copies.
