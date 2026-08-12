# Building the iOS app on Linux

There is no Mac in this project's loop. The iOS app is compiled on Linux by the
`mobaiapp/iosbox` image, which pairs Clang/Swift targeting `arm64-apple-ios`
with `ld64.lld` and an iOS SDK extracted from Xcode.

```bash
tools/build-ios-linux.sh        # -> flutter_app/build/iosbox/Runner.ipa
```

## The SDK is not in the image

`iosbox` ships the toolchain but not Apple's SDK, which isn't redistributable.
It lives in a Docker volume (`iosbox-sdk`, ~516 MB) populated once from an
Xcode archive:

```bash
docker run --rm -v iosbox-sdk:/root/.iosbox -v /path/to:/x \
    mobaiapp/iosbox:latest iosbox setup /x/Xcode.xip
```

If that volume is missing the build script stops and tells you this.

## Why the app has no storyboards

**Do not reintroduce `Main.storyboard` or `LaunchScreen.storyboard` into the
launch path.** Storyboards and asset catalogs are compiled by `ibtool` and
`actool`, which exist only inside Xcode on macOS. On Linux they are simply
absent, so the build succeeds and quietly ships a bundle with no
`Main.storyboardc` in it. Every launch then dies with:

```
NSInvalidArgumentException: Could not find a storyboard named 'Main' in bundle
```

which looks like a signing or install fault and is neither. Two changes keep
the app off that path, and both must stay:

- `ios/Runner/SceneDelegate.swift` creates the `UIWindow` and the
  `FlutterViewController` in code, instead of letting UIKit instantiate them
  from `UISceneStoryboardFile`.
- `ios/Runner/Info.plist` uses a `UILaunchScreen` dictionary rather than
  `UILaunchStoryboardName`, and declares no `UIMainStoryboardFile`. The
  dictionary is deliberately empty: a `UIImageName` or `UIColorName` would have
  to resolve through an asset catalog, putting `actool` back in the loop.

The `.storyboard` files are still in the repo and still referenced by
`Runner.xcodeproj`, so a real Xcode build keeps working; nothing reads them at
runtime any more. The same code path serves both toolchains.

For the same reason the app has no icon in these builds -- `AppIcon` needs a
compiled `Assets.car`. Ship an icon by building on macOS, or by adding loose
PNGs plus `CFBundleIcons` entries.

## Info.plist must not lean on Xcode

`iosbox` does not read `Runner.xcodeproj`, and it expands only a fixed set of
build variables in `Info.plist` -- `$(EXECUTABLE_NAME)`,
`$(PRODUCT_BUNDLE_IDENTIFIER)`, `$(FLUTTER_BUILD_NAME)` and friends. Anything
else Xcode would have supplied has to be written out literally. Two cases bit
us, both of which produce a *running* app rather than a build error, so they
only show up on the device:

- **`$(PRODUCT_MODULE_NAME).SceneDelegate`** reached the device unexpanded.
  UIKit could not resolve a class by that name, so no scene ever connected and
  the app drew a plain black screen. It is now spelled `Runner.SceneDelegate`,
  which is exactly what Xcode substitutes.
- **`UIDeviceFamily` was absent.** Xcode injects it from
  `TARGETED_DEVICE_FAMILY = "1,2"`; without it iOS reads the app as
  iPhone-only and runs it on iPad in compatibility mode -- letterboxed at
  320x480 with the little rotate/zoom buttons in the corner. It is now declared
  in the plist as `[1, 2]` to match the project setting.

The symptom to watch for is an app that launches but renders nothing, or one
that renders at the wrong size. Dump the built plist and compare it against the
source before assuming the Dart side is at fault:

```bash
python3 -c "import plistlib;print(plistlib.load(open('flutter_app/build/iosbox/Runner.app/Info.plist','rb')))"
```

## Debug configuration only

`iosbox build` takes no configuration flag; it always produces a debug build
(`flutter_assets/kernel_blob.bin`, JIT). On a real device that needs a debugger
attached, so launch it through MobAI with `debug: true`:

```json
{"action": "open_app", "bundle_id": "com.vicemultiplatform.app", "debug": true}
```

A release/AOT iOS build still needs macOS -- the `ios` job in
`.github/workflows/build.yml` on `macos-14` is what covers that.

## Signing and installing

The IPA comes out unsigned. Signing happens at install time through MobAI,
which needs a valid Apple ID session; when that session lapses, `install_app`
fails with `signing failed: no valid cached credentials` and you re-authenticate
in the MobAI app.

## The native core

`libvicecore.dylib` and `libvicecore_vsid.dylib` are built for arm64 iOS by
`native/vice_core/ios/build.sh` and copied into `Runner.app/Frameworks` by
`tools/build-ios-linux.sh`. See `native/vice_core/ios/` for how VICE itself is
cross-compiled; three things there are worth knowing before touching it:

- **No `--wrap`.** The Linux and Android cores intercept a dozen VICE functions
  with `-Wl,--wrap=`. That is ELF-only; `ld64.lld` rejects `-wrap` outright.
  `build-core-ios.sh` reproduces it by renaming symbols with `llvm-objcopy`
  instead, which is what `--wrap` does internally.
- **The two targets wrap different symbol sets.** vsid runs with video disabled
  and does not wrap `video_canvas_*`, so the patched archives are staged per
  target. Sharing one patched `libarch.a` leaves those symbols undefined for
  `raster/` and `video/`, which still call them.
- **`c1541` cannot build for iOS** -- it calls `system()`, which the SDK marks
  unavailable. It is a standalone disk utility that the core never links, so
  the VICE build runs under `make -k` and is judged by whether the artifacts
  the core needs exist.

The dylibs are bundled rather than linked into the Runner binary: `iosbox`
regenerates its SwiftPM package on every build, so there is nowhere to add link
flags. That is why the Dart side dlopens them by absolute path
(`ViceNativePaths._iosFrameworkLibrary`) instead of using
`DynamicLibrary.process()` -- nothing else references them, so nothing else
would load them.

## path_provider does not work in this build

`path_provider` 2.6's Apple implementation goes through `package:objective_c`,
whose native asset fails to load here:

```
dlopen(objective_c.dylib): symbol not found in flat namespace '_Dart_PostInteger_DL'
```

This surfaced as a *"Failed to load libvicecore"* error that had nothing to do
with the core -- the ROM-directory lookup threw before the core was ever opened.
`ViceNativePaths._supportDirPath` sidesteps it on iOS by deriving the app's data
container from `Directory.systemTemp.parent` (`HOME` comes back empty in this
build). Anything else on iOS that reaches for `path_provider` will hit the same
wall until the native-asset problem is fixed.

## Container writes as root

`iosbox` runs as root and leaves root-owned files across the bind-mounted repo
-- including `.dart_tool/` and `linux/flutter/ephemeral/`. The *host* Flutter
then fails with "Flutter failed to delete a directory" on the next Android or
Linux build. `tools/build-ios-linux.sh` chowns the tree back afterwards; if you
run `iosbox` by hand, do the same:

```bash
docker run --rm -v "$PWD:/proj" alpine chown -R "$(id -u):$(id -g)" /proj
```
