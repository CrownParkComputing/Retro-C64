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
```

Those are produced by running VICE's own `configure`/`make` with
`--enable-headlessui` (see `native/vice_core/linux/build-vice-linux-headless.sh`
and, for Android, the NDK toolchain flags in
`native/vice_core/android/build.sh`). They are large, machine-specific and not
redistributable here, so **GitHub Actions cannot rebuild the native cores**.

Consequences, reflected in `.github/workflows/build.yml`:

- **Android** — the arm64 `.so` files are **committed** under
  `flutter_app/android/app/src/main/jniLibs/arm64-v8a/`. CI consumes them and
  fails loudly if they're missing. Rebuild and re-commit them whenever
  `native/vice_core/bridge/*.c` changes.
- **Linux** — CI builds the Flutter bundle only. It ships *without*
  `libvicecore.so`, so the app will report "Failed to load libvicecore" until
  one is placed next to the executable. Build it locally with the CMake
  project in `native/vice_core/linux/`.
- **iOS** — no native build exists yet. There is no `.xcframework`, so the
  iOS job proves only that the Dart/Flutter layer compiles. Producing a
  runnable iOS app means building the bridge as a static library per-arch and
  packaging it, plus a CoreAudio backend (Linux uses ALSA, Android uses
  AAudio — see `native/vice_core/bridge/audio_backend*.c`).

## Rebuilding after changing bridge code

```bash
# Linux
cd native/vice_core/linux/build && cmake .. && cmake --build . -j4

# Android arm64 -> flutter_app/android/app/src/main/jniLibs/arm64-v8a/
native/vice_core/android/build.sh
```

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
