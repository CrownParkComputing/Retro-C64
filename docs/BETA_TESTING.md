# Getting a build to TestFlight

Everything the app needs is in the repo; what is left is Apple's paperwork,
which only an account holder can do.

## One-time setup (Apple side)

1. **Bundle ID** — register `com.vicemultiplatform.app` in the Developer
   portal, and create the matching app record in App Store Connect.
2. **Signing** — an Apple Distribution certificate plus an App Store
   provisioning profile for that bundle ID, installed in your keychain.
   Xcode's "Automatically manage signing" against your team does both.
3. **Export compliance** — already declared in `Info.plist`
   (`ITSAppUsesNonExemptEncryption = false`), so TestFlight will not ask
   per upload.
4. **Privacy manifest** — already in the bundle
   (`ios/Runner/PrivacyInfo.xcprivacy`), so uploads will not come back with
   ITMS-91053.

## Building the IPA

```bash
cd flutter_app
flutter build ipa --release --export-method app-store
# -> build/ios/ipa/*.ipa
```

Upload with Transporter.app, or:

```bash
xcrun altool --upload-app -t ios -f build/ios/ipa/*.ipa \
  -u <apple-id> -p <app-specific-password>
```

**Every upload needs a unique build number.** `pubspec.yaml` carries
`version: 1.0.0+1`; bump the `+N` each time, or pass
`--build-number=$(date +%s)`.

The native cores are already committed under
`flutter_app/ios/vicecore/iphoneos/`, so this needs no VICE source tree.
Rebuild them only when `native/vice_core/bridge/*.c` changes — see
[NATIVE_BUILD.md](NATIVE_BUILD.md).

## Or let CI do it

`.github/workflows/build.yml` builds and uploads a signed IPA on a push to
`main` or a `v*` tag, once these repository secrets exist:

- `APPSTORE_CERT_BASE64` — base64 of your distribution `.p12`
- `APPSTORE_CERT_PASSWORD`
- `APPSTORE_PROFILE_BASE64` — base64 of the `.mobileprovision`

Without them the job still builds an unsigned `.app`, so iOS breakage is
caught either way.

---

# Notes for testers

Paste something like this into TestFlight's "What to Test". The first
paragraph is not optional: without ROMs the app looks broken.

> **Before anything works, import C64 ROMs.** This app does not ship
> Commodore's ROMs. Open **Paths → C64 ROMs → Import ROMs...** and select a
> VICE ROM set — a folder, the loose files, or the zip. You need KERNAL,
> BASIC and the character generator; add the 1541 ROM too or `.d64` files
> will fail with `?DEVICE NOT PRESENT`.
>
> **Then add some games.** Either **Paths → Scan downloads** (finds `.d64`,
> `.t64`, `.tap`, `.crt`, `.prg`, `.sid` in a folder, including inside zips)
> or the file picker in the setup wizard. Games appear under **Games**,
> SID tunes under **Music** alongside the 20 bundled ones.
>
> **Worth exercising:** loading a disk and a tape title; sound; the
> on-screen joystick and the virtual keyboard; saving and resuming a state;
> rotating the device; leaving the app mid-game and coming back.

## Known limitations in this build

- The workbench is a sidebar-plus-content layout designed for a tablet.
  It works on an iPhone but is tight in portrait; the media filter tabs
  scroll sideways.
- Audio recovery after an interruption (a phone call, Siri) is implemented
  but has not been exercised on real hardware.
- Cover art is not fetched; every title shows a placeholder tile.
