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
  from `UISceneStoryboardFile`. It did not always do so, and the gap cost a
  day -- see "Nothing creates the window on an Xcode build" below.
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

## Nothing creates the window on an Xcode build

The symptom: the app launches, the scene connects, and the screen stays black.
No crash, no exception, nothing in the device log, and `flutter run` sits at
`Waiting for VM Service port to be available...` for ever. Dart never executes
-- not "runs and fails", *never starts*.

The cause is the seam between the two toolchains. On Linux, `iosbox` does not
compile the `AppDelegate.swift` in this repo: it substitutes its own, which
creates the window and the `FlutterViewController` itself. `SceneDelegate` was
therefore written only to *adopt* that window into the scene. The AppDelegate
committed here does no such thing -- it registers plugins on the implicit
engine and nothing else -- and no storyboard is wired to make one either
(that is the whole point of the section above). So on an Xcode build nothing
ever constructed a `FlutterViewController`, which is what brings the engine up.
No view controller, no engine, no Dart.

`SceneDelegate` now builds the window itself when there is none to adopt. The
Linux path still takes the adopt branch and is unaffected.

**This is not simulator-only.** The same path runs on device, so an
Xcode-built or Xcode Cloud-built IPA is black for testers while uploading and
validating perfectly -- Apple checks the bundle, not whether it draws.

### Checking another app for the same bug

Both apps in this family grew the same SceneDelegate from the same `iosbox`
constraint, so anything sharing that lineage has it. Two greps:

```sh
grep -c "UIWindow(windowScene" ios/Runner/SceneDelegate.swift        # 0 = never builds one
grep -c "UIMainStoryboardFile\|UISceneStoryboardFile" ios/Runner/Info.plist  # 0 = nothing else will
```

Both zero means every Xcode build of that app is black. A `Main.storyboard`
sitting in the project proves nothing: if neither key names it, it is inert.

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

## You cannot launch it by tapping the icon

Worth stating plainly, because it looks like a crash and it is not: the app
opens and closes instantly from the home screen. iOS kills a Flutter JIT
process within a second unless a debugger is attached, so the only way to
start an iosbox build is to attach one:

    tools/device-push.sh --run

That takes about two seconds and does nothing else -- no rebuild, no
reinstall. Anyone who needs to actually use the app on the device needs that
command, which also means **testers cannot run this build at all**. Only a
release/AOT build can be tapped, and that needs macOS. See "Shipping to
TestFlight" below.

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

`tools/device-push.sh` drives the whole thing -- start MobAI, wait for the
device, install, launch:

```bash
tools/device-push.sh --build --launch     # iOS
tools/device-push.sh --android --build    # Android, straight over adb
```

Three traps it exists to handle, because each one presents as "no device"
and none of them says so:

- **`systemctl start usbmuxd` is the wrong instinct.** There is no such unit
  and the distro package is not needed: MobAI extracts and runs its own
  usbmuxd from `~/.mobai/bin/usbmuxd`.
- **That usbmuxd is elevated with `pkexec`, which needs a polkit agent** to
  show the password dialog. `polkitd` running is not enough -- on Hyprland
  the agent is a separate user unit (`hyprpolkitagent`), and with it stopped
  pkexec cannot prompt, usbmuxd never starts, and the device list stays empty
  forever with nothing in the UI explaining why. The script starts it.
- **The device must be unlocked and trusted.** A locked or untrusted iPad is
  indistinguishable from an unplugged one at this layer.

Installing passes `resign: true` (the IPA is unsigned; without it you install
something iOS refuses to run) and launching passes `withDebugger: true` --
note that the HTTP API spells it `withDebugger` while the MCP tool calls the
same thing `debug`. Both come from `GET /api/v1/openapi.json`, which is worth
re-reading if a field ever stops working.

## The cores ship as .framework bundles, and must

`Runner.app/Frameworks/` holds `libvicecore.framework` and
`libvicecore_vsid.framework`, not the bare dylibs, and that is not cosmetic:
**a loose .dylib in Frameworks/ makes App Store validation reject the upload**
with

    90426: Invalid Swift Support. The SwiftSupport folder is missing.

Historically the only bare dylibs in an app's Frameworks/ were the Swift
runtime, so Apple's scanner reads them as an embedded Swift runtime and
demands a SwiftSupport folder -- which Xcode will never generate for a 15.0
deployment target, because ABI-stable Swift lives in the OS and there is
nothing to embed. The rejection is therefore unfixable while a bare dylib is
there, and every step of it misdirects:

- The error names Swift, which this app does not embed.
- Adding a SwiftSupport folder by hand converts it to 90429 ("aren't at the
  expected location /Payload/Runner.app/Frameworks") -- which is still
  reported when the files ARE at that exact location.
- `xcrun altool --validate-app` passes every time. The check only runs during
  server-side processing after the upload, so validation success means
  nothing here.
- Xcode's own GUI archive is identical to `xcodebuild archive`; neither
  produces SwiftSupport, so "let Xcode do it properly" is not a fix.

The Dart side loads them at `Frameworks/<name>.framework/<name>` -- see
`ViceNativePaths._iosFrameworkLibrary`. `tools/build-ios-linux.sh` still copies
the bare dylibs and needs the same treatment before its output can be shipped.

## Do not rewrite the frameworks' load commands

There was a build phase that raised the embedded frameworks' minimum OS with
`vtool -set-build-version ios $MIN $MIN`. It is gone, and it was wrong twice
over: the second argument is the **SDK** version, so every framework went out
claiming it was built against the iOS 15.0 SDK, and `-replace` drops the
`LC_BUILD_VERSION` tool records that identify the toolchain (`ntools` becomes
0). Apple reads both, concludes the app was built with an ancient SDK, and
demands the legacy embedded-Swift layout -- the same 90426/90429 above,
arriving with the boilerplate "rebuild your app using the current public (GM)
version of Xcode", which is literal advice and not boilerplate at all.

Check with `otool -l <binary> | grep -A6 LC_BUILD_VERSION` and compare to the
pristine engine copy under `bin/cache/artifacts/engine/ios-release/`. A
framework declaring a lower `minos` than the app is normal and permitted;
nothing needs raising.

## Signing on a machine with no Xcode account

Automatic signing cannot work without an Apple account in Xcode -- and it hunts
for a *development* profile even when exporting for the App Store. Use manual
signing, set on the **Runner target only**: passing
`PROVISIONING_PROFILE_SPECIFIER` on the `xcodebuild` command line applies it to
every Swift Package and Pod target too, none of which support profiles, and the
archive fails. Those settings are deliberately uncommitted -- they are
account-specific, and `main` keeps automatic signing so Xcode Cloud works.

Two keychain traps, both of which present as `errSecInternalComponent` and look
like a broken certificate:

- **Search-list order.** `codesign` resolves an identity hash to the first
  keychain in the list. If two keychains hold the same certificate and the
  first is locked, signing fails even though a working copy exists. Check with
  `security list-keychains -d user`.
- **A locked keychain lists its certificates perfectly happily.**
  `security find-identity` needs no private key, so a certificate can look
  present and valid right up to the moment codesign reaches for the key.

Also: openssl 3 writes PKCS#12 files Apple's Security framework cannot read
("MAC verification failed"). Export needs
`-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`.

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
   `com.vicemultiplatform.app`. The Android `applicationId` was renamed
   to `com.crownpark.retro_c64` with the shared-sidebar refactor. Mirror
   that here *before* creating the record, because a bundle ID can never
   be changed afterwards.
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

## Shipping via Xcode Cloud

Signing locally is a dead end on the shared VM, and the failure is worth
recognising because it looks like a project fault and is not one:

- Automatic signing insists on a *development* provisioning profile, Apple
  requires every development profile to name a registered device, and no device
  can be attached to a headless machine.
- Manual signing with a hand-made App Store profile gets past that and then
  fails `errSecInternalComponent` at the codesign step. The Apple Distribution
  key sits in `vice-build.keychain-db`, a keychain created by an earlier session
  whose password nobody recorded. `security find-identity` still *lists* the
  identity, because listing certificates does not need the key -- so the
  identity looks available right up to the moment it is used.

Xcode Cloud sidesteps all of it: it builds on Apple's infrastructure and
manages certificates and profiles itself, so no signing material has to exist
on this machine. It also delivers straight to App Store Connect, so there is no
IPA to hand to Transporter.

Three things make the project buildable there:

1. **`ios/ci_scripts/ci_post_clone.sh`** installs Flutter, which the Xcode Cloud
   images do not carry. Xcode Cloud runs `xcodebuild` directly rather than
   `flutter build`, and the Runner target's "Thin Binary" phase needs
   `FLUTTER_ROOT` from `Generated.xcconfig`, which only Flutter can write. Apple
   runs the script from the directory next to the Xcode project, hence
   `ios/ci_scripts/` and not the repo root. It pins the same Flutter version CI
   uses, because a newer toolchain rewrites `pubspec.lock` mid-build.
2. **Release uses automatic signing with `DEVELOPMENT_TEAM` committed.** This is
   the one place the "never commit the team" rule is deliberately broken: a
   hard-coded `PROVISIONING_PROFILE_SPECIFIER` naming a profile that exists in
   one local keychain would fail every cloud build.
3. **`ios/scripts/raise_framework_min_os.sh`** runs as the Runner target's last
   build phase. Validation **90068** rejects an upload whose embedded binaries
   declare a `MinimumOSVersion` below Apple's floor, and two sources here sit
   below it regardless of `IPHONEOS_DEPLOYMENT_TARGET`: the Flutter engine ships
   `Flutter.framework` and `App.framework` at its own floor, and the committed
   `libvicecore*.dylib` were cross-compiled at 13.0 and cannot be rebuilt here.
   The phase patches both the `Info.plist` key and the Mach-O
   `LC_BUILD_VERSION` load command, because Apple reads the load command too,
   then re-signs each item with `EXPANDED_CODE_SIGN_IDENTITY` -- the identity
   Xcode resolved for the build, which is what makes it work under cloud-managed
   signing. The bare dylibs need the loop of their own that they get: they carry
   no `Info.plist`, so the load command is the only record of the version.

The deployment target is therefore **15.0**, not 13.0. Raising it is not
optional -- Xcode 26 will not submit lower -- and it drops iOS 13 and 14
devices.

Setting the workflow up is a GUI step that cannot be scripted: in Xcode,
*Product > Xcode Cloud > Create Workflow*, or create it in App Store Connect
under the app's Xcode Cloud tab. Point it at this repository, archive the
`Runner` scheme, and add a **TestFlight (Internal Testing Only)** post-action.
Xcode Cloud builds from the remote, so the branch has to be pushed first.

`version:` in `pubspec.yaml` still governs `CFBundleVersion`, and App Store
Connect still refuses a number it has already seen. Builds 1 and 2 are spent.
