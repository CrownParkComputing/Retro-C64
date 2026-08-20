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
  and for the same reason: a Mac has no way to rebuild the *device* dylibs
  (the cross-compile needs the VICE object tree, which is not in this repo),
  so without the checked-in copies a `git clone` on macOS produces an app that
  installs and then dies at "Failed to load libvicecore". Both toolchains read
  that one directory — the Xcode "Embed Frameworks" phase on macOS, and
  `tools/build-ios-linux.sh` on Linux — but not the same *file*: Linux
  refreshes `<core>.framework/<core>` from `<core>.dylib` at package time,
  while Xcode ships the committed framework binary as-is. Update both, or a
  TestFlight build quietly carries different code from a dev build.
  Rebuild and re-commit them whenever `native/vice_core/bridge/*.c` changes:

  ```bash
  native/vice_core/ios/build.sh
  cp native/vice_core/ios/build/libvicecore{,_vsid}.dylib \
     flutter_app/ios/Frameworks/
  ```

  There is deliberately no `.xcframework`: these are arm64 **device** dylibs
  only, matching the arm64-only Android build.

### The resource API needs every slice rebuilt

`vice_core_{get,set}_resource_*` and `vice_core_dump_resources` (added
2026-08-19, they are what the Core screen edits) live in the shared
`bridge/vice_bridge.c`, so **all four artifacts** — Android `.so`, iOS device
dylib, the binary inside each `.framework`, and the Mac-built simulator slice —
have to be rebuilt or one platform silently lacks the API.

The Dart side looks those five symbols up **softly**: an older core still
loads and `ViceCore.hasResourceApi` answers false, so the Core screen says
"this build of the core has no resource access" instead of the app dying at
`DynamicLibrary.lookup`. That is a safety net for drift between slices, not a
licence to leave one behind.

- **iOS Simulator** — a separate slice, built **on a Mac** by
  `native/vice_core/ios/build-core-simulator.sh`, committed under
  `flutter_app/ios/vicecore/iphonesimulator/`, and swapped into the built
  `.app` by `tools/run-simulator.sh`. A device dylib cannot be loaded there at
  all (*"incompatible platform (have 'iOS', need 'iOS-simulator')"*).

  It is a Mac-only script because the simulator needs `iPhoneSimulator.sdk`,
  and the `iosbox-sdk` volume that serves the device cross-build carries
  `iPhoneOS.platform` only. Two substitutions follow from having no container:
  the `--wrap` symbol renaming uses `ld -r -alias` + `-unexported_symbol`
  instead of `llvm-objcopy --redefine-sym` (Xcode ships no objcopy), and
  `pkg-config` is stubbed to answer "not found", which is true — nothing on a
  Mac is linkable into a simulator binary.

  **Rebuild it whenever the bridge changes**, alongside the device cores.
  These were once prebuilt blobs nothing could regenerate; they went stale by
  a fix they never received, and every `.d64` failed in the simulator for
  weeks after the bug was fixed on device. That reads as a live regression and
  is not one.

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

# iOS arm64 device -> copy into flutter_app/ios/Frameworks/ and commit
native/vice_core/ios/build.sh                  # SKIP_VICE=1 to relink only
for c in libvicecore libvicecore_vsid; do
  cp "native/vice_core/ios/build/$c.dylib" "flutter_app/ios/Frameworks/$c.dylib"
  cp "native/vice_core/ios/build/$c.dylib" "flutter_app/ios/Frameworks/$c.framework/$c"
done

# iOS arm64 simulator -> ON A MAC; writes into ios/vicecore/iphonesimulator/
native/vice_core/ios/build-core-simulator.sh
```

All three iOS artifacts come from the same `bridge/*.c`. Changing the bridge
and rebuilding only one of them is how they drift apart, and the drift shows
up as an emulator bug on whichever target was left behind.

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
