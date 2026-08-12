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
- **iOS** — built from **Linux**, no Xcode and no Mac, by
  `native/vice_core/ios/build.sh`. It cross-compiles VICE for
  `arm64-apple-ios` against an SDK extracted from Xcode and links
  `libvicecore.dylib` / `libvicecore_vsid.dylib` with the bridge and a
  CoreAudio backend (`bridge/audio_backend_ios.m`, the third implementation of
  `audio_backend.h` alongside ALSA and AAudio).

  Like Android, these **are committed**, under `flutter_app/ios/Frameworks/`,
  and for the same reason: a Mac has no way to rebuild them (the cross-compile
  needs the VICE object tree, which is not in this repo), so without the
  checked-in copies a `git clone` on macOS produces an app that installs and
  then dies at "Failed to load libvicecore". Both toolchains read that one
  directory — the Xcode "Embed Frameworks" phase on macOS, and
  `tools/build-ios-linux.sh` on Linux — so the two IPAs ship the same bytes.
  Rebuild and re-commit them whenever `native/vice_core/bridge/*.c` changes:

  ```bash
  native/vice_core/ios/build.sh
  cp native/vice_core/ios/build/libvicecore{,_vsid}.dylib \
     flutter_app/ios/Frameworks/
  ```

  There is deliberately no `.xcframework`: these are arm64 **device** dylibs
  only, matching the arm64-only Android build. The iOS Simulator is x86_64/
  arm64-simulator and would need a second slice nobody here builds, so the app
  runs on real hardware only.

  Read `docs/IOS_BUILD.md` before changing any of it — the ELF-only `--wrap`
  trick used here does not exist on Mach-O, and nothing in the launch path may
  depend on a storyboard or asset catalog, because `ibtool`/`actool` are
  macOS-only.

## Rebuilding after changing bridge code

```bash
# Linux
cd native/vice_core/linux/build && cmake .. && cmake --build . -j4

# Android arm64 -> flutter_app/android/app/src/main/jniLibs/arm64-v8a/
native/vice_core/android/build.sh

# iOS arm64 -> copy into flutter_app/ios/Frameworks/ and commit
native/vice_core/ios/build.sh
cp native/vice_core/ios/build/libvicecore{,_vsid}.dylib flutter_app/ios/Frameworks/
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
