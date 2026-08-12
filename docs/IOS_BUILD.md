# Building the iOS app

There are two iOS toolchains here and they do different jobs. Pick by what you
need:

| | Linux (`iosbox`) | macOS (Xcode) |
|---|---|---|
| Configuration | debug/JIT only | release/AOT |
| Signing | unsigned; signed at install by MobAI | Apple Distribution cert |
| App icon | none (no `actool`) | yes |
| Good for | the fast device-test loop | **anything going to TestFlight or the App Store** |

`iosbox` cannot produce a store build — it has exactly two commands (`setup`,
`build`), `build` takes no configuration flag, and codesigning needs Apple's
own tools. **The App Store path is a Mac**: either the `ios` job in
`.github/workflows/build.yml` on `macos-14`, or a checkout on a real/rented
Mac. Both are covered in "Shipping to TestFlight" at the bottom.

The rest of this document is the Linux path, which is where most of the
hard-won detail lives; nearly all of it (storyboards, `Info.plist`, the native
core) applies to both.

## Building on Linux

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

Both toolchains take the dylibs from the **committed** copies in
`flutter_app/ios/Frameworks/`, never from `native/vice_core/ios/build/`:

- **macOS** -- the Runner target's *Embed Frameworks* build phase copies them
  into `Runner.app/Frameworks` with `CodeSignOnCopy`, so they are re-signed
  with whatever identity signs the app. App Store validation rejects an
  embedded dylib signed by anyone else.
- **Linux** -- `tools/build-ios-linux.sh` copies the same two files in after
  `iosbox` has run, then repacks the IPA.

Rebuild them with `native/vice_core/ios/build.sh` and **copy the output into
`flutter_app/ios/Frameworks/` and commit it**, or the change ships on neither
platform. See `docs/NATIVE_BUILD.md`.

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

It also re-resolves `pubspec.lock` with its own newer Flutter, bumping `meta`
and `test_api` past what the pinned `FLUTTER_VERSION` (3.41.9) allows. Leave
the lock at what the pinned toolchain produces -- `git checkout
flutter_app/pubspec.lock && flutter pub get` -- or CI rewrites it right back on
the next run.

## Shipping to TestFlight / the App Store

This needs a Mac (or the `macos-14` CI job). On a fresh clone:

```bash
cd flutter_app
flutter pub get
flutter build ipa --release --export-method app-store
```

Before the first upload, four things have to be true:

1. **The bundle ID is registered** in the Apple Developer portal and an app
   record exists in App Store Connect. It is currently
   `com.vicemultiplatform.app`, which no longer matches the app's name --
   change it *before* creating the record, because a bundle ID can never be
   changed afterwards.
2. **An Apple Distribution certificate and an App Store provisioning profile**
   for that bundle ID are installed in the Mac's keychain. For CI instead, set
   the repo secrets the workflow already reads: `APPSTORE_CERT_BASE64`,
   `APPSTORE_CERT_PASSWORD`, `APPSTORE_PROFILE_BASE64`.
3. **The native cores are committed** under `flutter_app/ios/Frameworks/`. The
   build succeeds without them and then dies on launch; CI checks explicitly.
4. **`version:` in `pubspec.yaml` is bumped.** App Store Connect rejects a
   build whose `CFBundleVersion` it has already seen, and the error arrives
   after the upload, not before it.

Upload the resulting `build/ios/ipa/*.ipa` with Transporter or
`xcrun altool --upload-app`. Encryption compliance
(`ITSAppUsesNonExemptEncryption`) is already declared in `Info.plist`, so the
build should reach testers without a manual answer in the console.
